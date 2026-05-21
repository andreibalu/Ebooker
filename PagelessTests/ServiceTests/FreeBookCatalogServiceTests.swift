//
//  FreeBookCatalogServiceTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

@MainActor
struct FreeBookCatalogServiceTests {

    // MARK: - Seed validation (no network needed)

    @Test func seedsAreNonEmpty() {
        #expect(!FreeBookCatalogService.bookSeeds.isEmpty)
    }

    @Test func seedsHaveValidFields() {
        for seed in FreeBookCatalogService.bookSeeds {
            #expect(!seed.id.isEmpty)
            #expect(!seed.title.isEmpty)
            #expect(!seed.author.isEmpty)
            #expect(!seed.description.isEmpty)
            #expect(!seed.archiveIdentifier.isEmpty)
            #expect(seed.estimatedSizeMB > 0)
        }
    }

    @Test func seedIdsAreUnique() {
        let ids = FreeBookCatalogService.bookSeeds.map(\.id)
        #expect(ids.count == Set(ids).count, "Seed IDs must be unique")
    }

    @Test func seedArchiveIdentifiersAreUnique() {
        let identifiers = FreeBookCatalogService.bookSeeds.map(\.archiveIdentifier)
        #expect(identifiers.count == Set(identifiers).count)
    }

    // MARK: - API fetching (mock network)

    @Test func allEntriesReturnsMappedEntries() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let entries = await FreeBookCatalogService.allEntries(session: session)
        #expect(entries.count == FreeBookCatalogService.bookSeeds.count)
        FreeBookCatalogService.resetCache()
    }

    @Test func allEntriesHaveNonEmptyTracks() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let entries = await FreeBookCatalogService.allEntries(session: session)
        for entry in entries {
            #expect(!entry.tracks.isEmpty, "Entry '\(entry.title)' has no tracks")
        }
        FreeBookCatalogService.resetCache()
    }

    @Test func allEntriesPreserveSeedOrder() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let entries = await FreeBookCatalogService.allEntries(session: session)
        let seedIds = FreeBookCatalogService.bookSeeds.map(\.id)
        let entryIds = entries.map(\.id)
        #expect(entryIds == seedIds)
        FreeBookCatalogService.resetCache()
    }

    @Test func allEntriesSkipsFailedFetches() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.failFirstHandler)
        FreeBookCatalogService.resetCache()
        let entries = await FreeBookCatalogService.allEntries(session: session)
        // At least some entries succeed (all but the first seed)
        #expect(entries.count < FreeBookCatalogService.bookSeeds.count)
        FreeBookCatalogService.resetCache()
    }

    @Test func availableEntriesExcludesDownloadedIds() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let all = await FreeBookCatalogService.allEntries(session: session)
        guard let firstId = all.first?.id else { return }
        let available = await FreeBookCatalogService.availableEntries(excluding: [firstId], session: session)
        #expect(available.count == all.count - 1)
        #expect(!available.contains(where: { $0.id == firstId }))
        FreeBookCatalogService.resetCache()
    }

    @Test func availableEntriesReturnsAllWhenNoneDownloaded() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let all = await FreeBookCatalogService.allEntries(session: session)
        let available = await FreeBookCatalogService.availableEntries(excluding: [], session: session)
        #expect(available.count == all.count)
        FreeBookCatalogService.resetCache()
    }

    @Test func tracksHavePositiveDuration() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let entries = await FreeBookCatalogService.allEntries(session: session)
        for entry in entries {
            for track in entry.tracks {
                #expect(track.durationSeconds > 0, "Track '\(track.title)' has non-positive duration")
            }
        }
        FreeBookCatalogService.resetCache()
    }

    @Test func tracksHaveValidDownloadURLs() async throws {
        let session = URLSession.makeMockSession(handler: MockArchiveHandler.validHandler)
        FreeBookCatalogService.resetCache()
        let entries = await FreeBookCatalogService.allEntries(session: session)
        for entry in entries {
            for track in entry.tracks {
                #expect(track.downloadURL.hasPrefix("https://archive.org/download/"))
                #expect(track.downloadURL.hasSuffix(".mp3"))
            }
        }
        FreeBookCatalogService.resetCache()
    }
}

// MARK: - Mock URLSession

extension URLSession {
    static func makeMockSession(handler: @escaping (URL) -> (Data?, URLResponse?, Error?)) -> URLSession {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URL) -> (Data?, URLResponse?, Error?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (data, response, error) = handler(url)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Mock Response Handlers

private enum MockArchiveHandler {
    static func validHandler(url: URL) -> (Data?, URLResponse?, Error?) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let json = """
        {
          "files": [
            { "name": "track_01_64kb.mp3", "format": "64Kbps MP3", "length": "1200.0", "title": "Chapter 1", "track": "1", "size": "9600000" },
            { "name": "track_02_64kb.mp3", "format": "64Kbps MP3", "length": "1100.0", "title": "Chapter 2", "track": "2", "size": "8800000" }
          ]
        }
        """
        return (Data(json.utf8), response, nil)
    }

    static func failFirstHandler(url: URL) -> (Data?, URLResponse?, Error?) {
        // Fail requests for the first seed's identifier
        if url.absoluteString.contains(FreeBookCatalogService.bookSeeds[0].archiveIdentifier) {
            return (nil, nil, URLError(.notConnectedToInternet))
        }
        return validHandler(url: url)
    }
}
