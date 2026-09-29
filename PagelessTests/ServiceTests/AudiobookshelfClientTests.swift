import Foundation
import Testing
@testable import Pageless

@Suite(.serialized)
struct AudiobookshelfClientTests {
    private let base = URL(string: "https://books.example.test/")!

    @Test func successfulLoginStoresBothMobileTokens() async throws {
        let store = MockABSCredentialStore()
        MockABSURLProtocol.handler = { request in
            #expect(request.url?.path == "/login")
            #expect(request.value(forHTTPHeaderField: "x-return-tokens") == "true")
            return (200, Self.json(#"{"user":{"accessToken":"access","refreshToken":"refresh","token":"legacy"}}"#))
        }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        try await client.login(serverURL: base, username: "reader", password: "secret")
        #expect(try store.load()?.credential == .session(accessToken: "access", refreshToken: "refresh"))
    }

    @Test func apiKeyUsesDocumentedBearerHeader() async throws {
        let store = MockABSCredentialStore()
        MockABSURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/authorize")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
            return (200, Self.json("{}"))
        }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        try await client.connect(serverURL: base, apiKey: "key")
        #expect(try store.load()?.credential == .apiKey("key"))
    }

    @Test func unauthorizedRequestRefreshesAndRetriesOnce() async throws {
        let scenario = Scenario()
        MockABSURLProtocol.handler = { request in scenario.reply(to: request) }
        let client = makeSessionClient()
        let libraries = try await client.libraries()
        #expect(libraries.map(\.id) == ["lib1"])
        #expect(scenario.refreshes == 1)
        #expect(scenario.requests == 2)
    }

    @Test func concurrentUnauthorizedRequestsShareRefresh() async throws {
        let scenario = Scenario()
        MockABSURLProtocol.handler = { request in scenario.reply(to: request) }
        let client = makeSessionClient()
        let results = try await withThrowingTaskGroup(of: [ABSLibrary].self) { group in
            for _ in 0..<12 { group.addTask { try await client.libraries() } }
            var all: [[ABSLibrary]] = []
            for try await value in group { all.append(value) }
            return all
        }
        #expect(results.count == 12)
        #expect(scenario.refreshes == 1)
    }

    @Test func paginationPreservesPageOrder() async throws {
        MockABSURLProtocol.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let page = components.queryItems?.first(where: { $0.name == "page" })?.value
            #expect(components.queryItems?.first(where: { $0.name == "limit" })?.value == "2")
            if page == "0" {
                return (200, Self.json(Self.page(ids: ["a", "b"], page: 0)))
            }
            return (200, Self.json(Self.page(ids: ["c"], page: 1)))
        }
        let items = try await makeSessionClient().allLibraryItems(libraryID: "lib1", limit: 2)
        #expect(items.map(\.id) == ["a", "b", "c"])
    }

    @Test func garbageResponseIsTyped() async throws {
        MockABSURLProtocol.handler = { _ in (200, Self.json("<html>maintenance</html>")) }
        do {
            _ = try await makeSessionClient().libraries()
            Issue.record("Expected unreadable response")
        } catch let error as AudiobookshelfError {
            #expect(error == .unreadableResponse)
        }
    }

    @Test func progressWriteThenRead() async throws {
        MockABSURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/me/progress/item1")
            if request.httpMethod == "PATCH" {
                guard let data = Self.bodyData(from: request),
                      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    Issue.record("Missing progress JSON body")
                    return (400, Data())
                }
                #expect(body["currentTime"] as? Double == 31.5)
                #expect(body["duration"] as? Double == 120)
                #expect(body["progress"] as? Double == 0.2625)
                return (200, Self.json("{}"))
            }
            return (200, Self.json(#"{"libraryItemId":"item1","duration":120,"progress":0.2625,"currentTime":31.5,"isFinished":false}"#))
        }
        let client = makeSessionClient()
        try await client.updateProgress(itemID: "item1", update: .init(duration: 120, currentTime: 31.5, isFinished: false))
        let progress = try await client.mediaProgress(itemID: "item1")
        #expect(progress?.currentTime == 31.5)
        #expect(progress?.libraryItemId == "item1")
    }

    @Test func itemAndPlaybackResolveAuthenticatedMediaRequests() async throws {
        let track = #"{"index":1,"startOffset":0,"duration":120,"title":"Chapter 1","contentUrl":"/s/item/item1/Chapter%201.mp3","mimeType":"audio/mpeg"}"#
        MockABSURLProtocol.handler = { request in
            if request.url?.path == "/api/items/item1/play" {
                #expect(request.httpMethod == "POST")
                return (200, Self.json(#"{"id":"play1","libraryItemId":"item1","audioTracks":[\#(track)],"chapters":[{"id":1,"start":0,"end":120,"title":"One"}]}"#))
            }
            #expect(request.url?.path == "/api/items/item1")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "1")
            return (200, Self.json(#"{"id":"item1","libraryId":"lib1","mediaType":"book","media":{"metadata":{"title":"Book","authorName":"Author"},"duration":120,"audioTracks":[\#(track)],"chapters":[{"id":1,"start":0,"end":120,"title":"One"}]}}"#))
        }
        let client = makeSessionClient()
        let item = try await client.item(id: "item1")
        #expect(item.media.audioTracks?.count == 1)
        #expect(item.media.chapters?.first?.title == "One")
        let playback = try await client.startPlayback(itemID: "item1")
        #expect(playback.audioTracks.count == 1)
        let stream = try await client.streamRequest(for: playback.audioTracks[0])
        #expect(stream.url?.path == "/s/item/item1/Chapter 1.mp3")
        #expect(stream.value(forHTTPHeaderField: "Authorization") == "Bearer old")
        let cover = try await client.coverRequest(itemID: "item1")
        #expect(cover.url?.path == "/api/items/item1/cover")
        #expect(cover.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func allProgressUsesCurrentServerRouteAndEnvelope() async throws {
        MockABSURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/me/progress")
            return (200, Self.json(#"{"mediaProgress":[{"libraryItemId":"item1","duration":100,"progress":0.5,"currentTime":50,"isFinished":false}]}"#))
        }
        let progress = try await makeSessionClient().allMediaProgress()
        #expect(progress.map(\.libraryItemId) == ["item1"])
    }

    // MARK: - Stream URLs (tokens only at play time)

    private static let track = ABSAudioTrack(index: 1, startOffset: 0, duration: 20, title: "chapter-01.mp3",
                                             contentUrl: "/api/items/item1/file/42", mimeType: "audio/mpeg")

    @Test func storedStreamURLIsSameOriginAndTokenless() async throws {
        let client = makeSessionClient()
        let stored = try await client.storedStreamURL(for: Self.track)
        #expect(stored.absoluteString == "https://books.example.test/api/items/item1/file/42")
        #expect(!stored.absoluteString.contains("token"))
        #expect(!stored.absoluteString.contains("old"))
        #expect(AudiobookshelfLibraryService.containsCredential(stored) == false)
    }

    @Test func storedStreamURLStripsATokenSmuggledInByTheServer() async throws {
        let client = makeSessionClient()
        let track = ABSAudioTrack(index: 1, startOffset: 0, duration: 20, title: "chapter-01.mp3",
                                  contentUrl: "/api/items/item1/file/42?token=leak&x=1", mimeType: nil)
        let stored = try await client.storedStreamURL(for: track)
        #expect(stored.absoluteString == "https://books.example.test/api/items/item1/file/42?x=1")
    }

    @Test func streamURLAppendsTheCurrentToken() async throws {
        let url = try await makeSessionClient().streamURL(for: Self.track)
        #expect(url.absoluteString == "https://books.example.test/api/items/item1/file/42?token=old")

        let keyStore = MockABSCredentialStore(ABSConnection(baseURL: base, credential: .apiKey("k3y")))
        let keyClient = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: keyStore)
        let keyURL = try await keyClient.streamURL(for: Self.track)
        #expect(URLComponents(url: keyURL, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "token", value: "k3y")])
    }

    @Test func crossOriginTrackURLsAreRejected() async throws {
        let client = makeSessionClient()
        let foreign = ABSAudioTrack(index: 1, startOffset: 0, duration: 1, title: "x",
                                    contentUrl: "https://evil.example/steal.mp3", mimeType: nil)
        await #expect(throws: AudiobookshelfError.invalidMediaURL) { try await client.storedStreamURL(for: foreign) }
        await #expect(throws: AudiobookshelfError.invalidMediaURL) { try await client.streamURL(for: foreign) }
    }

    @Test func playbackURLUsesAFreshTokenWithoutRefreshingWhenFarFromExpiry() async throws {
        let access = Self.jwt(["exp": Date().addingTimeInterval(3 * 3600).timeIntervalSince1970, "type": "access"])
        let store = MockABSCredentialStore(ABSConnection(baseURL: base, credential: .session(accessToken: access, refreshToken: "r")))
        MockABSURLProtocol.handler = { _ in
            Issue.record("No network expected")
            return (500, Data())
        }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        let url = try await client.playbackURL(forStoredURL: URL(string: "https://books.example.test/api/items/item1/file/42")!)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == access)
    }

    @Test func playbackURLRefreshesANearlyExpiredSessionFirst() async throws {
        let access = Self.jwt(["exp": Date().addingTimeInterval(120).timeIntervalSince1970, "type": "access"])
        let store = MockABSCredentialStore(ABSConnection(baseURL: base, credential: .session(accessToken: access, refreshToken: "r"), username: "reader"))
        MockABSURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/refresh")
            return (200, Self.json(#"{"user":{"accessToken":"fresh","refreshToken":"r2"}}"#))
        }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        let url = try await client.playbackURL(forStoredURL: URL(string: "https://books.example.test/api/items/item1/file/42")!)
        #expect(url.absoluteString == "https://books.example.test/api/items/item1/file/42?token=fresh")
        #expect(try store.load()?.credential == .session(accessToken: "fresh", refreshToken: "r2"))
        #expect(try store.load()?.username == "reader")
    }

    @Test func playbackURLRefusesAStoredURLFromAnotherServer() async throws {
        let client = makeSessionClient()
        await #expect(throws: AudiobookshelfError.invalidMediaURL) {
            try await client.playbackURL(forStoredURL: URL(string: "https://other.example/api/items/item1/file/42")!)
        }
    }

    @Test func refreshFinishingAfterAServerSwitchNeverOverwritesOrLeaksIntoTheNewConnection() async throws {
        let access = Self.jwt(["exp": Date().addingTimeInterval(120).timeIntervalSince1970, "type": "access"])
        let serverA = ABSConnection(baseURL: base, credential: .session(accessToken: access, refreshToken: "a-refresh"))
        let serverB = ABSConnection(baseURL: URL(string: "https://other.example")!,
                                    credential: .session(accessToken: "b-access", refreshToken: "b-refresh"))
        let store = MockABSCredentialStore(serverA)
        MockABSURLProtocol.handler = { request in
            #expect(request.url?.host == "books.example.test")
            // The user disconnects and signs in to server B while A's refresh is on the wire.
            try? store.clear()
            try? store.save(serverB)
            return (200, Self.json(#"{"user":{"accessToken":"a-new","refreshToken":"a-new-refresh"}}"#))
        }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        await #expect(throws: AudiobookshelfError.notConnected) {
            try await client.playbackURL(forStoredURL: URL(string: "https://books.example.test/api/items/item1/file/42")!)
        }
        #expect(try store.load() == serverB)
    }

    @Test func playbackURLNeverAppendsAnotherServersTokenAfterTheConnectionChanges() async throws {
        let access = Self.jwt(["exp": Date().addingTimeInterval(120).timeIntervalSince1970, "type": "access"])
        let serverA = ABSConnection(baseURL: base, credential: .session(accessToken: access, refreshToken: "a-refresh"))
        let farAccess = Self.jwt(["exp": Date().addingTimeInterval(3 * 3600).timeIntervalSince1970, "type": "access"])
        let serverB = ABSConnection(baseURL: URL(string: "https://other.example")!,
                                    credential: .session(accessToken: farAccess, refreshToken: "b-refresh"))
        let store = MockABSCredentialStore(serverA)
        MockABSURLProtocol.handler = { _ in
            try? store.save(serverB)
            return (200, Self.json(#"{"user":{"accessToken":"a-new","refreshToken":"a-new-refresh"}}"#))
        }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        do {
            let url = try await client.playbackURL(forStoredURL: URL(string: "https://books.example.test/api/items/item1/file/42")!)
            Issue.record("Unexpected URL \(url)")
        } catch {}
        #expect(try store.load() == serverB)
    }

    @Test func disconnectDuringRefreshLeavesNoCredentialsBehind() async throws {
        let access = Self.jwt(["exp": Date().addingTimeInterval(120).timeIntervalSince1970, "type": "access"])
        let store = MockABSCredentialStore(ABSConnection(baseURL: base, credential: .session(accessToken: access, refreshToken: "r")))
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        MockABSURLProtocol.handler = { _ in
            try? store.clear()
            return (200, Self.json(#"{"user":{"accessToken":"a-new","refreshToken":"a-new-refresh"}}"#))
        }
        await #expect(throws: (any Error).self) {
            try await client.playbackURL(forStoredURL: URL(string: "https://books.example.test/api/items/item1/file/42")!)
        }
        #expect(try store.load() == nil)
    }

    // MARK: - Connect errors

    @Test func inactiveAPIKeyIsDistinguishedFromAWrongKey() async throws {
        MockABSURLProtocol.handler = { _ in (401, Self.json("Unauthorized")) }
        let apiKeyToken = Self.jwt(["keyId": "abc", "name": "phone", "type": "api", "iat": 1])
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: MockABSCredentialStore())
        await #expect(throws: AudiobookshelfError.inactiveAPIKey) { try await client.connect(serverURL: base, apiKey: apiKeyToken) }
        await #expect(throws: AudiobookshelfError.badCredentials) { try await client.connect(serverURL: base, apiKey: "typo") }
    }

    @Test func apiKeyConnectRemembersTheUsername() async throws {
        let store = MockABSCredentialStore()
        MockABSURLProtocol.handler = { _ in (200, Self.json(#"{"user":{"username":"reader"}}"#)) }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
        try await client.connect(serverURL: base, apiKey: "key")
        #expect(try store.load()?.username == "reader")
    }

    @Test func aServerWithoutTheLoginRouteIsNotAudiobookshelf() async throws {
        MockABSURLProtocol.handler = { _ in (404, Self.json("<html>Not found</html>")) }
        let client = AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: MockABSCredentialStore())
        await #expect(throws: AudiobookshelfError.notAudiobookshelfServer) {
            try await client.login(serverURL: base, username: "a", password: "b")
        }
    }

    // MARK: - Server address parsing

    @Test func serverAddressParsing() throws {
        #expect(try AudiobookshelfClient.serverURL(from: "abs.example.com").absoluteString.hasPrefix("https://abs.example.com"))
        #expect(try AudiobookshelfClient.serverURL(from: "  https://abs.example.com/  ").host() == "abs.example.com")
        #expect(try AudiobookshelfClient.serverURL(from: "192.168.1.20:13378").scheme == "http")
        #expect(try AudiobookshelfClient.serverURL(from: "localhost:13378").port == 13378)
        #expect(try AudiobookshelfClient.serverURL(from: "nas.local").scheme == "http")
        #expect(try AudiobookshelfClient.serverURL(from: "http://example.org").scheme == "http")
        #expect(throws: AudiobookshelfError.invalidServerURL) { try AudiobookshelfClient.serverURL(from: "") }
        #expect(throws: AudiobookshelfError.invalidServerURL) { try AudiobookshelfClient.serverURL(from: "ftp://files.example") }
        #expect(throws: AudiobookshelfError.invalidServerURL) { try AudiobookshelfClient.serverURL(from: "my server") }
    }

    @Test func localNetworkHostClassification() {
        for host in ["localhost", "nas.local", "nas", "10.0.0.2", "127.0.0.1:13378", "172.20.1.1", "192.168.0.5", "100.100.1.1"] {
            #expect(AudiobookshelfClient.isLocalNetworkHost(host), "\(host)")
        }
        for host in ["abs.example.com", "8.8.8.8", "172.32.0.1", "myhost.ts.net"] {
            #expect(!AudiobookshelfClient.isLocalNetworkHost(host), "\(host)")
        }
    }

    // MARK: - Expanded item shape (ABS 2.36)

    @Test func expandedItemReadsTracksAndTagTitles() throws {
        let json = #"{"id":"i","libraryId":"l","mediaType":"book","addedAt":1700000000000,"media":{"metadata":{"title":"Frankenstein","authorName":"Mary Shelley","narratorName":""},"duration":40,"coverPath":null,"audioTracks":null,"tracks":[{"index":2,"startOffset":20,"duration":20,"title":"chapter-02.mp3","contentUrl":"/api/items/i/file/2","mimeType":"audio/mpeg","metaTags":{}},{"index":1,"startOffset":0,"duration":20,"title":"chapter-01.mp3","contentUrl":"/api/items/i/file/1","mimeType":"audio/mpeg","metaTags":{"tagTitle":"Letter 1"}}],"chapters":[]}}"#
        let item = try JSONDecoder().decode(ABSLibraryItem.self, from: Data(json.utf8))
        #expect(item.media.playableTracks.map(\.displayTitle) == ["Letter 1", "chapter-02"])
        #expect(item.media.hasCover == false)
        #expect(item.media.chapterCount == 2)
        #expect(item.media.metadata.displayNarrator == nil)
        #expect(item.addedDate == Date(timeIntervalSince1970: 1_700_000_000))
    }

    private static func jwt(_ payload: [String: Any]) -> String {
        func b64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let body = b64(try! JSONSerialization.data(withJSONObject: payload))
        return "\(header).\(body).signature"
    }

    private func makeSessionClient() -> AudiobookshelfClient {
        let store = MockABSCredentialStore(ABSConnection(baseURL: base,
            credential: .session(accessToken: "old", refreshToken: "refresh-old")))
        return AudiobookshelfClient(session: MockABSURLProtocol.session(), credentials: store)
    }

    private static func json(_ string: String) -> Data { Data(string.utf8) }
    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer[..<count])
        }
        return data
    }
    private static func page(ids: [String], page: Int) -> String {
        let items = ids.map { #"{"id":"\#($0)","libraryId":"lib1","mediaType":"book","media":{"metadata":{"title":"Book"}}}"# }
        return #"{"results":[\#(items.joined(separator: ","))],"total":3,"limit":2,"page":\#(page)}"#
    }
}

private final class Scenario: @unchecked Sendable {
    private let lock = NSLock()
    private var refreshCount = 0
    private var requestCount = 0
    var refreshes: Int { lock.lock(); defer { lock.unlock() }; return refreshCount }
    var requests: Int { lock.lock(); defer { lock.unlock() }; return requestCount }

    func reply(to request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        if request.url?.path == "/auth/refresh" {
            refreshCount += 1
            return (200, Data(#"{"user":{"accessToken":"new","refreshToken":"refresh-new"}}"#.utf8))
        }
        requestCount += 1
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" {
            return (401, Data())
        }
        return (200, Data(#"{"libraries":[{"id":"lib1","name":"Books","mediaType":"book"}]}"#.utf8))
    }
}
