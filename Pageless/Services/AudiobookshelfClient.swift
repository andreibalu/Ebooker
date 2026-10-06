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
    /// The API key is well-formed but the server refuses it — ABS creates keys inactive by default.
    case inactiveAPIKey
    /// The device has no network path at all (distinct from a server that doesn't answer).
    case offline
    /// Something answered, but not an Audiobookshelf server (e.g. 404 on `/login`).
    case notAudiobookshelfServer
}

/// Standalone ABS transport. URLSession is injectable so no running server is needed in tests.
actor AudiobookshelfClient {
    private let session: URLSession
    private let credentials: any ABSCredentialStoring
    /// Identity of the connection a refresh was started for. A refresh may only be shared with, or
    /// saved over, the exact connection (server + refresh token) that created it.
    private struct RefreshIdentity: Equatable {
        let baseURL: URL
        let refreshToken: String
    }
    private var refreshTask: (id: UUID, identity: RefreshIdentity, task: Task<ABSConnection, Error>)?

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
        invalidateRefresh()
        try credentials.save(ABSConnection(baseURL: baseURL,
                                           credential: .session(accessToken: access, refreshToken: refresh),
                                           username: response.user.username ?? username))
    }

    func connect(serverURL: URL, apiKey: String) async throws {
        let baseURL = try Self.normalized(serverURL)
        guard !apiKey.isEmpty else { throw AudiobookshelfError.badCredentials }
        let candidate = ABSConnection(baseURL: baseURL, credential: .apiKey(apiKey))
        let data: Data
        do {
            data = try await send(baseURL: baseURL, path: ["api", "authorize"], method: "POST",
                                  body: nil, headers: [:], auth: candidate.credential)
        } catch AudiobookshelfError.badCredentials {
            // ABS answers a disabled key and a mistyped key with the same bare 401. A key that
            // decodes as an ABS API-key token was issued by the server, so it is almost certainly
            // switched off (new keys start inactive) rather than wrong.
            throw ABSJWT.isAudiobookshelfAPIKey(apiKey)
                ? AudiobookshelfError.inactiveAPIKey
                : AudiobookshelfError.badCredentials
        }
        let username = (try? JSONDecoder().decode(LoginResponse.self, from: data))?.user.username
        invalidateRefresh()
        try credentials.save(ABSConnection(baseURL: baseURL, credential: candidate.credential, username: username))
    }

    func disconnect() throws {
        invalidateRefresh()
        try credentials.clear()
    }

    /// Cancels any in-flight token refresh so it can neither be reused by, nor save credentials
    /// over, a different connection. Call whenever the active connection is replaced or removed.
    func invalidateRefresh() {
        refreshTask?.task.cancel()
        refreshTask = nil
    }

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

    /// Token-less absolute URL for a track — the only form ever written to SwiftData (synced rows
    /// reach the user's iCloud, so a credential there would be a leak).
    func storedStreamURL(for track: ABSAudioTrack) throws -> URL {
        let connection = try requiredConnection()
        return try Self.sameOriginURL(track.contentUrl, base: connection.baseURL)
    }

    /// Playable URL for AVPlayer, which cannot send headers: the verified `?token=` form works for
    /// both a login JWT and an API key. Never persist the result.
    func streamURL(for track: ABSAudioTrack) throws -> URL {
        let connection = try requiredConnection()
        let url = try Self.sameOriginURL(track.contentUrl, base: connection.baseURL)
        return try Self.appendingToken(Self.token(for: connection.credential), to: url)
    }

    /// Resolves a stored (token-less) track URL at play time. Refreshes a login session that is
    /// close to expiry first, so a book added long ago keeps playing across JWT rotations and a
    /// fresh token covers the range requests AVPlayer keeps making while it streams.
    func playbackURL(forStoredURL stored: URL) async throws -> URL {
        var connection = try requiredConnection()
        var url = try Self.sameOriginURL(stored.absoluteString, base: connection.baseURL)
        if case .session(let access, _) = connection.credential,
           let expiry = ABSJWT.expiry(of: access),
           expiry.timeIntervalSinceNow < Self.minimumStreamTokenLifetime {
            _ = try await refresh(after: access)
            // The connection may have changed while suspended: re-read the active one and re-check
            // the origin so a token is never appended to another server's URL.
            connection = try requiredConnection()
            url = try Self.sameOriginURL(stored.absoluteString, base: connection.baseURL)
        }
        return try Self.appendingToken(Self.token(for: connection.credential), to: url)
    }

    /// A stream token must outlive a long listening stretch; below this the session refreshes.
    static let minimumStreamTokenLifetime: TimeInterval = 45 * 60

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
        let identity = RefreshIdentity(baseURL: current.baseURL, refreshToken: refresh)
        if let existing = refreshTask {
            if existing.identity == identity { return try await existing.task.value }
            existing.task.cancel()
        }
        let task = Task<ABSConnection, Error> {
            let data = try await send(baseURL: identity.baseURL, path: ["auth", "refresh"],
                                      method: "POST", body: nil, headers: ["x-refresh-token": refresh], auth: nil)
            let response: LoginResponse = try decode(data)
            guard let newAccess = response.user.accessToken, !newAccess.isEmpty,
                  let newRefresh = response.user.refreshToken, !newRefresh.isEmpty else {
                throw AudiobookshelfError.unreadableResponse
            }
            try Task.checkCancellation()
            // Only save over the connection this refresh was created for.
            guard let active = try credentials.load(), active.baseURL == identity.baseURL,
                  case .session(_, let activeRefresh) = active.credential,
                  activeRefresh == identity.refreshToken else {
                throw AudiobookshelfError.notConnected
            }
            let renewed = ABSConnection(baseURL: identity.baseURL,
                                        credential: .session(accessToken: newAccess, refreshToken: newRefresh),
                                        username: active.username)
            try credentials.save(renewed)
            return renewed
        }
        let id = UUID()
        refreshTask = (id, identity, task)
        defer { if refreshTask?.id == id { refreshTask = nil } }
        return try await task.value
    }

    private func send(baseURL: URL, path: [String], method: String, body: Data?,
                      query: [URLQueryItem] = [], headers: [String: String],
                      auth: ABSCredential?) async throws -> Data {
        var request = URLRequest(url: try makeURL(baseURL: baseURL, path: path, query: query))
        // A wrong LAN address should fail in seconds, not after URLSession's default minute.
        request.timeoutInterval = 20
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let auth { Self.applyAuth(auth, to: &request) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.mapped(error)
        }
        guard let http = response as? HTTPURLResponse else { throw AudiobookshelfError.unreadableResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401:
            if path == ["login"] { throw AudiobookshelfError.badCredentials }
            if case .some(.apiKey) = auth { throw AudiobookshelfError.badCredentials }
            throw AudiobookshelfError.expiredToken
        case 404 where path == ["login"] || path == ["api", "authorize"]:
            throw AudiobookshelfError.notAudiobookshelfServer
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

    /// Parses what a person types into the server field. A bare host gets `https://`, except
    /// hosts that can only be on the local network (localhost, `.local`, private IPv4), which get
    /// `http://` because that is how a home server is almost always reached. A Tailscale MagicDNS
    /// name with an explicit port (`nas.tailnet.ts.net:13378`) also gets `http://`: that is the
    /// server's own plain listener, while the bare name usually fronts `tailscale serve` HTTPS.
    nonisolated static func serverURL(from input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { throw AudiobookshelfError.invalidServerURL }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            guard !text.contains("://") else { throw AudiobookshelfError.invalidServerURL }
            let host = text.split(separator: "/").first.map(String.init) ?? text
            let isTailnetWithPort = host.contains(":") && isTailnetHost(host.split(separator: ":")[0].lowercased())
            text = (isLocalNetworkHost(host) || isTailnetWithPort ? "http://" : "https://") + text
        }
        while text.hasSuffix("/") && text.count > "https://".count { text.removeLast() }
        guard let url = URL(string: text) else { throw AudiobookshelfError.invalidServerURL }
        return try normalized(url)
    }

    nonisolated static func isLocalNetworkHost(_ hostAndPort: String) -> Bool {
        let host = (hostAndPort.split(separator: ":").first.map(String.init) ?? hostAndPort).lowercased()
        if host == "localhost" || host.hasSuffix(".local") || !host.contains(".") { return true }
        return isPrivateIPv4(host)
    }

    /// True when plain http to `url` should trigger the "not using HTTPS" warning before any
    /// credential is sent. Plain http is allowed everywhere (ATS `NSAllowsArbitraryLoads`); it is
    /// silent only for hosts that are reachable solely over a LAN or a private VPN overlay.
    nonisolated static func needsInsecureConnectionWarning(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host(percentEncoded: false) else { return false }
        return !isPrivateNetworkHost(host)
    }

    /// Hosts whose traffic stays on the user's own network or a private overlay (Tailscale), so
    /// plain http there is the normal self-hosting setup rather than an exposure to the internet.
    /// Takes a bare host (no port); IPv6 literals may be bracketed or not.
    nonisolated static func isPrivateNetworkHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if host.contains(":") { return isPrivateIPv6(host) }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if isTailnetHost(host) { return true }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return isPrivateIPv4(host) }
        return !host.contains(".")   // unqualified name, resolved by the LAN/VPN search domain
    }

    nonisolated private static func isTailnetHost(_ host: String) -> Bool {
        host.hasSuffix(".ts.net")
    }

    /// RFC 1918, loopback, link-local and the 100.64.0.0/10 CGNAT range Tailscale assigns from.
    nonisolated private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, let b) where (16...31).contains(b): return true
        case (100, let b) where (64...127).contains(b): return true   // CGNAT / Tailscale
        default: return false
        }
    }

    /// Loopback, link-local (fe80::/10), unique-local (fc00::/7, incl. Tailscale's fd7a:115c:a1e0::/48).
    nonisolated private static func isPrivateIPv6(_ host: String) -> Bool {
        let address = host.split(separator: "%").first.map(String.init) ?? host   // drop zone id
        if address == "::1" { return true }
        guard let first = address.split(separator: ":", omittingEmptySubsequences: false).first,
              !first.isEmpty, let word = UInt16(first, radix: 16) else { return false }
        return word & 0xFE00 == 0xFC00 || word & 0xFFC0 == 0xFE80
    }

    nonisolated private static func mapped(_ error: URLError) -> AudiobookshelfError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .badURL, .unsupportedURL:
            return .invalidServerURL
        default:
            return .unreachableServer
        }
    }

    nonisolated private static func sameOriginURL(_ string: String, base: URL) throws -> URL {
        guard let url = URL(string: string, relativeTo: base)?.absoluteURL,
              url.host == base.host, url.scheme == base.scheme, url.port == base.port else {
            throw AudiobookshelfError.invalidMediaURL
        }
        // Stored URLs must never carry a credential, even one that slipped into the input.
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AudiobookshelfError.invalidMediaURL
        }
        parts.queryItems = parts.queryItems?.filter { $0.name != "token" }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        guard let clean = parts.url else { throw AudiobookshelfError.invalidMediaURL }
        return clean
    }

    nonisolated private static func appendingToken(_ token: String, to url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AudiobookshelfError.invalidMediaURL
        }
        var items = parts.queryItems ?? []
        items.append(URLQueryItem(name: "token", value: token))
        parts.queryItems = items
        guard let result = parts.url else { throw AudiobookshelfError.invalidMediaURL }
        return result
    }

    nonisolated private static func token(for credential: ABSCredential) -> String {
        switch credential {
        case .session(let access, _): access
        case .apiKey(let key): key
        }
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
    struct User: Decodable {
        let accessToken: String?
        let refreshToken: String?
        var username: String? = nil
    }
}

/// Reads (never verifies) the payload of an ABS-issued JWT. Used only for UX decisions — the
/// server stays the authority on whether a token is valid.
nonisolated enum ABSJWT {
    static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    static func expiry(of token: String) -> Date? {
        guard let exp = payload(of: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// ABS API keys are JWTs whose payload carries `type: "api"` and a `keyId` (verified on 2.36.1).
    static func isAudiobookshelfAPIKey(_ token: String) -> Bool {
        guard let payload = payload(of: token) else { return false }
        return payload["type"] as? String == "api" && payload["keyId"] != nil
    }
}
private nonisolated struct PlaybackRequest: Encodable {
    let deviceInfo: DeviceInfo
    let supportedMimeTypes: [String]
    struct DeviceInfo: Encodable { let clientName: String }
}
