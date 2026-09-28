import Foundation

nonisolated enum AudiobookshelfError: Error, Equatable {
    case notConnected
    case invalidServerURL
    case unreachableServer
    case badCredentials
    case expiredToken
    case serverError(status: Int)
    case unreadableResponse
    case invalidMediaURL
}

/// Standalone ABS transport. URLSession is injectable so no running server is needed in tests.
actor AudiobookshelfClient {
    private let session: URLSession
    private let credentials: any ABSCredentialStoring
    private var refreshTask: Task<ABSConnection, Error>?

    init(session: URLSession = .shared, credentials: any ABSCredentialStoring = ABSKeychainCredentialStore()) {
        self.session = session
        self.credentials = credentials
    }

    func connection() throws -> ABSConnection? { try credentials.load() }

    func login(serverURL: URL, username: String, password: String) async throws {
        let baseURL = try Self.normalized(serverURL)
        let body = try JSONEncoder().encode(LoginRequest(username: username, password: password))
        let data = try await send(baseURL: baseURL, path: ["login"], method: "POST", body: body,
                                  headers: ["x-return-tokens": "true"], auth: nil)
        let response: LoginResponse = try decode(data)
        guard let access = response.user.accessToken, !access.isEmpty,
              let refresh = response.user.refreshToken, !refresh.isEmpty else {
            throw AudiobookshelfError.unreadableResponse
        }
        try credentials.save(ABSConnection(baseURL: baseURL,
                                           credential: .session(accessToken: access, refreshToken: refresh)))
    }

    func connect(serverURL: URL, apiKey: String) async throws {
        let baseURL = try Self.normalized(serverURL)
        guard !apiKey.isEmpty else { throw AudiobookshelfError.badCredentials }
        let candidate = ABSConnection(baseURL: baseURL, credential: .apiKey(apiKey))
        _ = try await send(baseURL: baseURL, path: ["api", "authorize"], method: "POST",
                           body: nil, headers: [:], auth: candidate.credential)
        try credentials.save(candidate)
    }

    func disconnect() throws { try credentials.clear() }

    func libraries() async throws -> [ABSLibrary] {
        let data = try await request(path: ["api", "libraries"])
        let response: LibrariesResponse = try decode(data)
        return response.libraries
    }

    func libraryItems(libraryID: String, page: Int, limit: Int = 50) async throws -> ABSPage {
        guard page >= 0, limit > 0 else { throw AudiobookshelfError.unreadableResponse }
        let data = try await request(path: ["api", "libraries", libraryID, "items"],
                                     query: [URLQueryItem(name: "page", value: String(page)),
                                             URLQueryItem(name: "limit", value: String(limit)),
                                             URLQueryItem(name: "collapseseries", value: "0")])
        return try decode(data)
    }

    func allLibraryItems(libraryID: String, limit: Int = 50) async throws -> [ABSLibraryItem] {
        var items: [ABSLibraryItem] = []
        var pageNumber = 0
        while true {
            let page = try await libraryItems(libraryID: libraryID, page: pageNumber, limit: limit)
            guard page.page == pageNumber, page.limit == limit else { throw AudiobookshelfError.unreadableResponse }
            items.append(contentsOf: page.results)
            if items.count >= page.total { return items }
            guard !page.results.isEmpty else { throw AudiobookshelfError.unreadableResponse }
            pageNumber += 1
        }
    }

    func item(id: String) async throws -> ABSLibraryItem {
        try decode(await request(path: ["api", "items", id],
                                 query: [URLQueryItem(name: "expanded", value: "1")]))
    }

    func coverURL(itemID: String, width: Int = 400) throws -> URL {
        let connection = try requiredConnection()
        guard width > 0 else { throw AudiobookshelfError.invalidMediaURL }
        return try makeURL(baseURL: connection.baseURL, path: ["api", "items", itemID, "cover"],
                           query: [URLQueryItem(name: "width", value: String(width))])
    }

    func coverRequest(itemID: String, width: Int = 400) throws -> URLRequest {
        let connection = try requiredConnection()
        var request = URLRequest(url: try coverURL(itemID: itemID, width: width))
        Self.applyAuth(connection.credential, to: &request)
        return request
    }

    func startPlayback(itemID: String) async throws -> ABSPlaybackSession {
        let body = try JSONEncoder().encode(PlaybackRequest(deviceInfo: .init(clientName: "Unpaged"),
                                                             supportedMimeTypes: ["audio/mpeg", "audio/mp4", "audio/flac", "audio/ogg"]))
        return try decode(await request(path: ["api", "items", itemID, "play"], method: "POST", body: body))
    }

    /// The returned request includes authentication. A bare stream URL is not sufficient for AVPlayer.
    func streamRequest(for track: ABSAudioTrack) throws -> URLRequest {
        let connection = try requiredConnection()
        guard let url = URL(string: track.contentUrl, relativeTo: connection.baseURL)?.absoluteURL,
              url.host == connection.baseURL.host, url.scheme == connection.baseURL.scheme,
              url.port == connection.baseURL.port else { throw AudiobookshelfError.invalidMediaURL }
        var request = URLRequest(url: url)
        Self.applyAuth(connection.credential, to: &request)
        return request
    }

    func mediaProgress(itemID: String) async throws -> ABSMediaProgress? {
        do { return try decode(await request(path: ["api", "me", "progress", itemID])) }
        catch AudiobookshelfError.serverError(status: 404) { return nil }
    }

    func allMediaProgress() async throws -> [ABSMediaProgress] {
        let response: MediaProgressResponse = try decode(await request(path: ["api", "me", "progress"]))
        return response.mediaProgress
    }

    func updateProgress(itemID: String, update: ABSProgressUpdate) async throws {
        guard update.duration >= 0, update.currentTime >= 0 else { throw AudiobookshelfError.unreadableResponse }
        let body = try JSONEncoder().encode(update)
        _ = try await request(path: ["api", "me", "progress", itemID], method: "PATCH", body: body)
    }

    private func request(path: [String], method: String = "GET", body: Data? = nil,
                         query: [URLQueryItem] = []) async throws -> Data {
        let connection = try requiredConnection()
        do {
            return try await send(baseURL: connection.baseURL, path: path, method: method, body: body,
                                  query: query, headers: [:], auth: connection.credential)
        } catch AudiobookshelfError.expiredToken {
            guard case .session(let failedAccess, _) = connection.credential else {
                throw AudiobookshelfError.badCredentials
            }
            let renewed = try await refresh(after: failedAccess)
            return try await send(baseURL: renewed.baseURL, path: path, method: method, body: body,
                                  query: query, headers: [:], auth: renewed.credential)
        }
    }

    private func refresh(after failedAccess: String) async throws -> ABSConnection {
        let current = try requiredConnection()
        guard case .session(let access, let refresh) = current.credential else {
            throw AudiobookshelfError.expiredToken
        }
        if access != failedAccess { return current }
        if let refreshTask { return try await refreshTask.value }
        let task = Task<ABSConnection, Error> {
            let data = try await send(baseURL: current.baseURL, path: ["auth", "refresh"],
                                      method: "POST", body: nil, headers: ["x-refresh-token": refresh], auth: nil)
            let response: LoginResponse = try decode(data)
            guard let newAccess = response.user.accessToken, !newAccess.isEmpty,
                  let newRefresh = response.user.refreshToken, !newRefresh.isEmpty else {
                throw AudiobookshelfError.unreadableResponse
            }
            let renewed = ABSConnection(baseURL: current.baseURL,
                                        credential: .session(accessToken: newAccess, refreshToken: newRefresh))
            try credentials.save(renewed)
            return renewed
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func send(baseURL: URL, path: [String], method: String, body: Data?,
                      query: [URLQueryItem] = [], headers: [String: String],
                      auth: ABSCredential?) async throws -> Data {
        var request = URLRequest(url: try makeURL(baseURL: baseURL, path: path, query: query))
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let auth { Self.applyAuth(auth, to: &request) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AudiobookshelfError.unreadableResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401:
            if path == ["login"] { throw AudiobookshelfError.badCredentials }
            if case .some(.apiKey) = auth { throw AudiobookshelfError.badCredentials }
            throw AudiobookshelfError.expiredToken
        case 502, 503, 504: throw AudiobookshelfError.unreachableServer
        default: throw AudiobookshelfError.serverError(status: http.statusCode)
        }
    }

    private func requiredConnection() throws -> ABSConnection {
        guard let connection = try credentials.load() else { throw AudiobookshelfError.notConnected }
        return connection
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AudiobookshelfError.unreadableResponse }
    }

    private func makeURL(baseURL: URL, path: [String], query: [URLQueryItem] = []) throws -> URL {
        var url = baseURL
        for component in path { url.appendPathComponent(component) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AudiobookshelfError.invalidServerURL
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let result = parts.url else { throw AudiobookshelfError.invalidServerURL }
        return result
    }

    private static func normalized(_ url: URL) throws -> URL {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw AudiobookshelfError.invalidServerURL
        }
        return url.absoluteURL
    }

    private static func applyAuth(_ credential: ABSCredential, to request: inout URLRequest) {
        switch credential {
        case .session(let access, _): request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        case .apiKey(let key): request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }
}

private nonisolated struct LoginRequest: Encodable { let username: String; let password: String }
private nonisolated struct LibrariesResponse: Decodable { let libraries: [ABSLibrary] }
private nonisolated struct MediaProgressResponse: Decodable { let mediaProgress: [ABSMediaProgress] }
private nonisolated struct LoginResponse: Decodable {
    let user: User
    struct User: Decodable { let accessToken: String?; let refreshToken: String? }
}
private nonisolated struct PlaybackRequest: Encodable {
    let deviceInfo: DeviceInfo
    let supportedMimeTypes: [String]
    struct DeviceInfo: Encodable { let clientName: String }
}
