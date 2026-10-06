import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct BrowseLibriVoxViewModelTests {
    @Test func incompleteIndexSearchesLibriVoxAndPersistsResults() async throws {
        let container = try makeContainer()
        let remote = RemoteSearchStub(results: [makeAPIBook(id: "remote-1", title: "Remote Result")])
        let viewModel = BrowseLibriVoxViewModel(
            remoteSearch: remote,
            isLocalSearchReady: { false }
        )

        await viewModel.performSearch(query: "remote", modelContext: container.mainContext)

        #expect(remote.queries == ["remote"])
        #expect(viewModel.searchResults.map(\.id) == ["remote-1"])
        #expect(viewModel.searchSource == .librivox)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LibriVoxBook>()) == 1)
    }

    @Test func completeIndexSearchesLocallyWithoutNetwork() async throws {
        let container = try makeContainer()
        container.mainContext.insert(makeBook(id: "local-1", title: "Local Treasure"))
        try container.mainContext.save()
        let remote = RemoteSearchStub(results: [makeAPIBook(id: "remote-1", title: "Remote Result")])
        let viewModel = BrowseLibriVoxViewModel(
            remoteSearch: remote,
            isLocalSearchReady: { true }
        )

        await viewModel.performSearch(query: "Treasure", modelContext: container.mainContext)

        #expect(remote.queries.isEmpty)
        #expect(viewModel.searchResults.map(\.id) == ["local-1"])
        #expect(viewModel.searchSource == .local)
    }

    @Test func incompleteOfflineSearchFallsBackToSavedMatches() async throws {
        let container = try makeContainer()
        container.mainContext.insert(makeBook(id: "saved-1", title: "Saved Treasure"))
        try container.mainContext.save()
        let remote = RemoteSearchStub(error: URLError(.notConnectedToInternet))
        let viewModel = BrowseLibriVoxViewModel(
            remoteSearch: remote,
            isLocalSearchReady: { false }
        )

        await viewModel.performSearch(query: "Treasure", modelContext: container.mainContext)

        #expect(viewModel.searchResults.map(\.id) == ["saved-1"])
        #expect(viewModel.searchSource == .savedFallback)
    }

    @Test func staleOpenedBookRefreshesRelevantMetadata() async throws {
        let container = try makeContainer()
        let book = makeBook(id: "stale-1", title: "Old Title")
        book.lastSyncedAt = Date(timeIntervalSince1970: 0)
        container.mainContext.insert(book)
        try container.mainContext.save()
        let remote = RemoteSearchStub(
            refreshedBook: makeAPIBook(id: "stale-1", title: "Fresh Title")
        )
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote)

        await viewModel.refreshBookIfStale(
            book,
            modelContext: container.mainContext,
            now: Date(timeIntervalSince1970: 100_000)
        )

        #expect(remote.fetchedIDs == ["stale-1"])
        #expect(book.title == "Fresh Title")
    }

    @Test func freshOpenedBookSkipsRemoteRefresh() async throws {
        let container = try makeContainer()
        let book = makeBook(id: "fresh-1")
        book.lastSyncedAt = Date(timeIntervalSince1970: 90_000)
        let remote = RemoteSearchStub(refreshedBook: makeAPIBook(id: "fresh-1", title: "Changed"))
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote)

        await viewModel.refreshBookIfStale(
            book,
            modelContext: container.mainContext,
            now: Date(timeIntervalSince1970: 100_000)
        )

        #expect(remote.fetchedIDs.isEmpty)
        #expect(book.title == "Local Book")
    }

    @Test func catalogBookResolvesExactLocalID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = makeBook(id: "book-42")
        context.insert(book)
        try context.save()

        let result = BrowseLibriVoxViewModel().catalogBook(
            id: "book-42",
            modelContext: context
        )

        #expect(result === book)
    }

    @Test func catalogBookReturnsNilForMissingID() throws {
        let container = try makeContainer()

        #expect(BrowseLibriVoxViewModel().catalogBook(
            id: "missing",
            modelContext: container.mainContext
        ) == nil)
    }

    // MARK: Filters while the catalog is incomplete

    @Test func languageFilterWorksDuringSyncFromCachedSubset() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeBook(id: "de-1", title: "Die Verwandlung", language: "German"))
        context.insert(makeBook(id: "en-1", title: "Jane Eyre"))
        try context.save()
        let remote = RemoteSearchStub(results: [makeAPIBook(id: "remote-1", title: "Remote")])
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote, isLocalSearchReady: { false })

        viewModel.selectedLanguage = "German"
        await viewModel.performSearch(query: "", modelContext: context)

        #expect(viewModel.searchResults.map(\.id) == ["de-1"])
        #expect(viewModel.searchSource == .partialCache)
        #expect(viewModel.isShowingPartialResults)
        #expect(remote.queries.isEmpty && remote.browsedGenres.isEmpty)
    }

    @Test func genreFilterDuringSyncUsesLiveFeedMergedWithCache() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeBook(id: "cached-1", title: "Cached Mystery", genres: ["Detective Fiction"]))
        context.insert(makeBook(id: "cached-2", title: "Cached Poems", genres: ["Poetry"]))
        try context.save()
        let remote = RemoteSearchStub(results: [
            makeAPIBook(id: "remote-1", title: "Remote Mystery", genres: ["Detective Fiction"]),
            makeAPIBook(id: "remote-2", title: "Long Remote Mystery", genres: ["Detective Fiction"], seconds: 40_000),
        ])
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote, isLocalSearchReady: { false })

        viewModel.selectedGenre = "Detective Fiction"
        viewModel.selectedDuration = .medium
        await viewModel.performSearch(query: "", modelContext: context)

        #expect(remote.browsedGenres == ["Detective Fiction"])
        #expect(viewModel.searchResults.map(\.id) == ["remote-1", "cached-1"])
        #expect(viewModel.searchSource == .librivox)
        #expect(!viewModel.isShowingPartialResults)
    }

    @Test func textSearchDuringSyncAppliesFiltersToLiveResults() async throws {
        let container = try makeContainer()
        let remote = RemoteSearchStub(results: [
            makeAPIBook(id: "en", title: "Faust"),
            makeAPIBook(id: "de", title: "Faust", language: "German"),
        ])
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote, isLocalSearchReady: { false })

        viewModel.selectedLanguage = "German"
        await viewModel.performSearch(query: "Faust", modelContext: container.mainContext)

        #expect(viewModel.searchResults.map(\.id) == ["de"])
    }

    @Test func offlineGenreFilterFallsBackToPartialCache() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeBook(id: "cached-1", title: "Cached Mystery", genres: ["Detective Fiction"]))
        context.insert(makeBook(id: "cached-2", title: "Cached Poems", genres: ["Poetry"]))
        try context.save()
        let remote = RemoteSearchStub(error: URLError(.notConnectedToInternet))
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote, isLocalSearchReady: { false })

        viewModel.selectedGenre = "Detective Fiction"
        await viewModel.performSearch(query: "", modelContext: context)

        #expect(viewModel.searchResults.map(\.id) == ["cached-1"])
        #expect(viewModel.searchSource == .savedFallback)
        #expect(viewModel.isShowingPartialResults)
    }

    @Test func filterMenusNeverShrinkWhileCatalogIsPartial() {
        let viewModel = BrowseLibriVoxViewModel(isLocalSearchReady: { false })
        viewModel.availableLanguages = ["English", "Latin"]
        #expect(viewModel.languageOptions.starts(with: BrowseLibriVoxViewModel.fallbackLanguages))
        #expect(viewModel.languageOptions.contains("Latin"))
    }

    // MARK: Sync lifecycle

    @Test func pageArrivalUpdatesActivePartialFilterBeforeSyncFinishes() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try insertCuratedClassics(into: context)
        let gate = SyncGate()
        let viewModel = BrowseLibriVoxViewModel(
            isLocalSearchReady: { false }, isSyncDue: { true }, isConnected: { true },
            syncRunner: gate.runner
        )
        viewModel.selectedLanguage = "German"
        await viewModel.performSearch(query: "", modelContext: context)
        #expect(viewModel.searchResults.isEmpty)
        viewModel.triggerSyncIfNeeded(modelContext: context)
        try await gate.waitForRuns(1)

        let store = await viewModel.catalogStore(for: context)
        let count = try await store.upsert([
            makeAPIBook(id: "new-de", title: "Neue Geschichte", language: "German"),
            makeAPIBook(id: "new-la", title: "Fabula", language: "Latin")
        ])
        gate.reportProgress(savedCount: count)
        try await waitUntil { viewModel.searchResults.map(\.id) == ["new-de"] }
        #expect(viewModel.isSyncInFlight)
        #expect(viewModel.languageOptions.contains("Latin"))
        gate.finish(.completed(processed: 2))
        try await waitUntil { !viewModel.isSyncInFlight }
    }

    @Test func repeatedTriggersAndForegroundsStartOnlyOneSync() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try insertCuratedClassics(into: context)
        let gate = SyncGate()
        let viewModel = BrowseLibriVoxViewModel(
            isLocalSearchReady: { false },
            isSyncDue: { true },
            isConnected: { true },
            syncRunner: gate.runner
        )

        viewModel.triggerSyncIfNeeded(modelContext: context)
        viewModel.triggerSyncIfNeeded(modelContext: context)
        viewModel.appWillEnterForeground()
        viewModel.forceRefresh(modelContext: context)
        try await gate.waitForRuns(1)
        viewModel.triggerSyncIfNeeded(modelContext: context)
        viewModel.appWillEnterForeground()

        #expect(viewModel.syncRunsStarted == 1)
        #expect(gate.runs == 1)
        gate.finish(.completed(processed: 0))
        try await waitUntil { !viewModel.isSyncInFlight }
        #expect(viewModel.syncState == .done)
        #expect(gate.runs == 1)
    }

    @Test func backgroundPausesAndForegroundResumesExactlyOnce() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try insertCuratedClassics(into: context)
        let gate = SyncGate()
        let viewModel = BrowseLibriVoxViewModel(
            isLocalSearchReady: { false },
            isSyncDue: { true },
            isConnected: { true },
            syncRunner: gate.runner
        )

        viewModel.triggerSyncIfNeeded(modelContext: context)
        try await gate.waitForRuns(1)

        viewModel.appDidEnterBackground()
        #expect(gate.lastFlag?.isRaised == true)
        // Coming back while the paused pass winds down must not start a second one...
        viewModel.appWillEnterForeground()
        viewModel.appWillEnterForeground()
        #expect(viewModel.syncRunsStarted == 1)

        // ...but once it stops, exactly one pass resumes (from the persisted cursor).
        gate.finish(.paused)
        try await gate.waitForRuns(2)
        #expect(viewModel.syncRunsStarted == 2)
        #expect(gate.lastFlag?.isRaised == false)
        gate.finish(.completed(processed: 0))
        try await waitUntil { !viewModel.isSyncInFlight }
        #expect(gate.runs == 2)
    }

    @Test func pausedInBackgroundStaysPausedUntilForeground() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try insertCuratedClassics(into: context)
        let gate = SyncGate()
        let viewModel = BrowseLibriVoxViewModel(
            isLocalSearchReady: { false },
            isSyncDue: { true },
            isConnected: { true },
            syncRunner: gate.runner
        )

        viewModel.triggerSyncIfNeeded(modelContext: context)
        try await gate.waitForRuns(1)
        viewModel.appDidEnterBackground()
        gate.finish(.paused)
        try await waitUntil { !viewModel.isSyncInFlight }
        #expect(viewModel.syncState == .paused(saved: LibriVoxCatalogSync.syncedBookCount))
        viewModel.triggerSyncIfNeeded(modelContext: context) // e.g. a view appearing in background
        #expect(gate.runs == 1)

        viewModel.appWillEnterForeground()
        try await gate.waitForRuns(2)
        gate.finish(.completed(processed: 0))
        try await waitUntil { !viewModel.isSyncInFlight }
    }

    @Test func offlineTriggerDoesNotStartSync() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try insertCuratedClassics(into: context)
        let gate = SyncGate()
        let viewModel = BrowseLibriVoxViewModel(
            isLocalSearchReady: { false },
            isSyncDue: { true },
            isConnected: { false },
            syncRunner: gate.runner
        )

        viewModel.triggerSyncIfNeeded(modelContext: context)
        try await waitUntil { viewModel.isOfflineWithCachedData }

        #expect(gate.runs == 0)
        #expect(viewModel.featuredBooks.count == BrowseLibriVoxViewModel.featuredBooksTarget)
    }

    private func insertCuratedClassics(into context: ModelContext) throws {
        for id in BrowseLibriVoxViewModel.curatedClassicIDs {
            context.insert(makeBook(id: id, title: "Classic \(id)"))
        }
        try context.save()
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
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

    private func makeBook(
        id: String,
        title: String = "Local Book",
        language: String = "English",
        genres: [String] = []
    ) -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: title,
            authorDisplay: "Local Author",
            bookDescription: "Description",
            language: language,
            totalTimeSecs: 3_600,
            genres: genres
        )
    }

    private func makeAPIBook(
        id: String,
        title: String,
        language: String = "English",
        genres: [String] = [],
        seconds: Int = 3_600
    ) -> LibriVoxAPIBook {
        LibriVoxAPIBook(
            id: id,
            title: title,
            description: "Description",
            totalTimeSecs: seconds,
            authors: [LibriVoxAPIAuthor(firstName: "Remote", lastName: "Author")],
            language: language,
            urlLibrivox: nil,
            urlIarchive: nil,
            urlRss: nil,
            coverartThumbnail: nil,
            genres: genres.enumerated().map { LibriVoxAPIGenre(id: "\($0.offset)", name: $0.element) }
        )
    }
}

@MainActor
private final class RemoteSearchStub: LibriVoxRemoteSearching {
    private(set) var queries: [String] = []
    private(set) var fetchedIDs: [String] = []
    private(set) var browsedGenres: [String] = []
    private let results: [LibriVoxAPIBook]
    private let refreshedBook: LibriVoxAPIBook?
    private let error: Error?

    init(
        results: [LibriVoxAPIBook] = [],
        refreshedBook: LibriVoxAPIBook? = nil,
        error: Error? = nil
    ) {
        self.results = results
        self.refreshedBook = refreshedBook
        self.error = error
    }

    func search(query: String) async throws -> [LibriVoxAPIBook] {
        queries.append(query)
        if let error { throw error }
        return results
    }

    func browse(genre: String) async throws -> [LibriVoxAPIBook] {
        browsedGenres.append(genre)
        if let error { throw error }
        return results
    }

    func fetchBook(id: String) async throws -> LibriVoxAPIBook? {
        fetchedIDs.append(id)
        if let error { throw error }
        return refreshedBook ?? results.first { $0.id == id }
    }
}

/// A sync runner the test finishes by hand, so overlapping triggers can be observed
/// while a pass is genuinely in flight.
@MainActor
private final class SyncGate {
    private(set) var runs = 0
    private(set) var lastFlag: LibriVoxSyncPauseFlag?
    private var pending: CheckedContinuation<LibriVoxSyncOutcome, Never>?
    private var onProgress: (@MainActor @Sendable (LibriVoxSyncProgress) -> Void)?

    var runner: BrowseLibriVoxViewModel.SyncRunner {
        { [unowned self] _, flag, onProgress in
            self.runs += 1
            self.lastFlag = flag
            self.onProgress = onProgress
            return await withCheckedContinuation { self.pending = $0 }
        }
    }

    func reportProgress(savedCount: Int) {
        onProgress?(LibriVoxSyncProgress(savedCount: savedCount, processedThisRun: 2))
    }

    func finish(_ outcome: LibriVoxSyncOutcome) {
        pending?.resume(returning: outcome)
        pending = nil
    }

    func waitForRuns(_ count: Int) async throws {
        for _ in 0..<500 where runs < count || pending == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(runs == count)
    }
}
