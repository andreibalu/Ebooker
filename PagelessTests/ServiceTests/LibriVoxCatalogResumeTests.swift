import Foundation
import os
import SwiftData
import Testing
@testable import Pageless

/// The full catalog sync commits page by page on a background `@ModelActor` and persists
/// a cursor, so pauses and failures resume where they stopped.
@MainActor
struct LibriVoxCatalogResumeTests {
    @Test func pausedSyncResumesFromLastCommittedPage() async throws {
        let container = try makeContainer()
        let store = await LibriVoxCatalogStore.make(container: container)
        let checkpoint = makeCheckpoint()
        let feed = FakeFeed(totalBooks: 120)
        let flag = LibriVoxSyncPauseFlag()

        // Background pause raised after the first committed page: the pass stops there.
        let first = try await LibriVoxCatalogSync.syncIfNeeded(
            store: store, checkpoint: checkpoint, feed: feed.feed, pauseFlag: flag
        ) { progress in
            if progress.processedThisRun == 50 { flag.raise() }
        }
        #expect(first == .paused)
        #expect(checkpoint.resumeOffset == 50)
        #expect(!checkpoint.isLocalSearchReady)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LibriVoxBook>()) == 50)

        let second = try await LibriVoxCatalogSync.syncIfNeeded(
            store: store, checkpoint: checkpoint, feed: feed.feed
        ) { _ in }
        #expect(second == .completed(processed: 70))
        #expect(feed.requestedOffsets == [0, 50, 100])
        #expect(checkpoint.resumeOffset == 0)
        #expect(checkpoint.isLocalSearchReady)
        #expect(checkpoint.syncedBookCount == 120)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LibriVoxBook>()) == 120)
    }

    @Test func failedPageKeepsCursorAndRetryDoesNotRestartAtZero() async throws {
        let container = try makeContainer()
        let store = await LibriVoxCatalogStore.make(container: container)
        let checkpoint = makeCheckpoint()
        let feed = FakeFeed(totalBooks: 150, failingOffset: 100)

        await #expect(throws: URLError.self) {
            _ = try await LibriVoxCatalogSync.syncIfNeeded(
                store: store, checkpoint: checkpoint, feed: feed.feed
            ) { _ in }
        }
        #expect(checkpoint.resumeOffset == 100)

        feed.failingOffset = nil
        let outcome = try await LibriVoxCatalogSync.syncIfNeeded(
            store: store, checkpoint: checkpoint, feed: feed.feed
        ) { _ in }
        #expect(outcome == .completed(processed: 50))
        #expect(Array(feed.requestedOffsets.dropFirst(3)) == [100, 150])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LibriVoxBook>()) == 150)
    }

    @Test func pageUpsertRefreshesRowsSeededOnTheMainContext() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try LibriVoxCatalogSync.seed([FakeFeed.book(id: "7", title: "Seeded")], into: context)
        let store = await LibriVoxCatalogStore.make(container: container)

        let count = try await store.upsert([FakeFeed.book(id: "7", title: "Synced"), FakeFeed.book(id: "8")])

        #expect(count == 2)
        let rows = try context.fetch(FetchDescriptor<LibriVoxBook>(sortBy: [SortDescriptor(\.id)]))
        #expect(rows.map(\.id) == ["7", "8"])
    }

    @Test func completedCatalogSkipsWithinADay() async throws {
        let container = try makeContainer()
        let store = await LibriVoxCatalogStore.make(container: container)
        let checkpoint = makeCheckpoint()
        checkpoint.markFullPassComplete(total: 0, at: Date(timeIntervalSince1970: 1_000))
        let feed = FakeFeed(totalBooks: 10)

        let outcome = try await LibriVoxCatalogSync.syncIfNeeded(
            store: store, checkpoint: checkpoint, feed: feed.feed,
            now: Date(timeIntervalSince1970: 1_000 + 3_600)
        ) { _ in }

        #expect(outcome == .skipped)
        #expect(feed.requestedOffsets.isEmpty)
    }

    private func makeCheckpoint() -> LibriVoxSyncCheckpoint {
        let suite = "LibriVoxCatalogResumeTests.\(UUID().uuidString)"
        return LibriVoxSyncCheckpoint(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LibriVoxBook.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// A deterministic 50-per-page catalog feed that records requested offsets.
private final class FakeFeed: Sendable {
    private struct State {
        var offsets: [Int] = []
        var failingOffset: Int?
    }

    private let totalBooks: Int
    private let state: OSAllocatedUnfairLock<State>

    init(totalBooks: Int, failingOffset: Int? = nil) {
        self.totalBooks = totalBooks
        self.state = OSAllocatedUnfairLock(initialState: State(failingOffset: failingOffset))
    }

    var requestedOffsets: [Int] { state.withLock { $0.offsets } }
    var failingOffset: Int? {
        get { state.withLock { $0.failingOffset } }
        set { state.withLock { $0.failingOffset = newValue } }
    }

    var feed: LibriVoxCatalogFeed {
        LibriVoxCatalogFeed(
            fullPage: { [self] offset in try self.page(at: offset) },
            sincePage: { _, _ in [] }
        )
    }

    private func page(at offset: Int) throws -> [LibriVoxAPIBook] {
        let shouldFail = state.withLock { state -> Bool in
            state.offsets.append(offset)
            return state.failingOffset == offset
        }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        let end = min(offset + 50, totalBooks)
        guard offset < end else { return [] }
        return (offset..<end).map { FakeFeed.book(id: "\($0)") }
    }

    static func book(id: String, title: String = "Book") -> LibriVoxAPIBook {
        LibriVoxAPIBook(
            id: id, title: title, description: "", totalTimeSecs: 3_600,
            authors: nil, language: "English", urlLibrivox: nil, urlIarchive: nil,
            urlRss: nil, coverartThumbnail: nil, genres: nil
        )
    }
}
