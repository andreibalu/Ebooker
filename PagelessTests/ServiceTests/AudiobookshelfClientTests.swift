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
