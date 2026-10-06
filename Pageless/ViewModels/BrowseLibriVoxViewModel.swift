//
//  BrowseLibriVoxViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData
import UIKit

nonisolated enum DurationFilter: String, CaseIterable, Identifiable, Sendable {
    case short     = "< 1 hr"
    case medium    = "1–3 hrs"
    case long      = "3–6 hrs"
    case extraLong = "6+ hrs"

    var id: String { rawValue }

    func matches(seconds: Int) -> Bool {
        switch self {
        case .short:     return seconds < 3_600
        case .medium:    return seconds >= 3_600  && seconds < 10_800
        case .long:      return seconds >= 10_800 && seconds < 21_600
        case .extraLong: return seconds >= 21_600
        }
    }
}

@MainActor
@Observable
final class BrowseLibriVoxViewModel {
    enum SearchSource: Equatable {
        /// Live LibriVox results merged with matching cached books (catalog incomplete).
        case librivox
        /// The complete local catalog.
        case local
        /// Offline: only books cached so far.
        case savedFallback
        /// Online, but the filter can't be asked of the feed (language/length only) or the
        /// feed failed — the cached subset, which is partial while the sync runs.
        case partialCache
    }

    enum SyncState: Equatable {
        case idle
        case syncing(fetched: Int)
        /// Stopped between pages because the app went to the background; resumes from the
        /// persisted cursor on return.
        case paused(saved: Int)
        case done
        case failed(String, isOffline: Bool)
    }

    /// Runs one sync pass. Injectable so tests can count and control passes.
    typealias SyncRunner = @MainActor (
        _ store: LibriVoxCatalogStore,
        _ pauseFlag: LibriVoxSyncPauseFlag,
        _ onProgress: @escaping @MainActor @Sendable (LibriVoxSyncProgress) -> Void
    ) async throws -> LibriVoxSyncOutcome

    var searchQuery: String = ""
    var searchResults: [LibriVoxBook] = []
    var searchSource: SearchSource? = nil
    var isSearchingLibriVox = false
    var searchFailureMessage: String? = nil
    var syncState: SyncState = .idle
    var backgroundUpdateMessage: String? = nil
    var featuredBooks: [LibriVoxBook] = []
    var todaysPick: LibriVoxBook? = nil

    private let remoteSearch: any LibriVoxRemoteSearching
    private let isLocalSearchReadyProvider: () -> Bool
    private let isSyncDueProvider: () -> Bool
    private let isConnectedProvider: () -> Bool
    private let syncRunner: SyncRunner

    init(
        remoteSearch: (any LibriVoxRemoteSearching)? = nil,
        isLocalSearchReady: (() -> Bool)? = nil,
        isSyncDue: (() -> Bool)? = nil,
        isConnected: (() -> Bool)? = nil,
        syncRunner: SyncRunner? = nil
    ) {
        self.remoteSearch = remoteSearch ?? LiveLibriVoxRemoteSearch()
        self.isLocalSearchReadyProvider = isLocalSearchReady ?? { LibriVoxCatalogSync.isLocalSearchReady }
        self.isSyncDueProvider = isSyncDue ?? { LibriVoxCatalogSync.isSyncDue }
        self.isConnectedProvider = isConnected ?? { NetworkMonitor.shared.isConnected }
        self.syncRunner = syncRunner ?? { store, pauseFlag, onProgress in
            try await LibriVoxCatalogSync.syncIfNeeded(
                store: store, pauseFlag: pauseFlag, onProgress: onProgress
            )
        }
    }

    var isLocalSearchReady: Bool { isLocalSearchReadyProvider() }

    /// True when the shown results come from an incomplete catalog — the browse screen
    /// says so instead of disabling search or filters.
    var isShowingPartialResults: Bool {
        guard !isLocalSearchReady else { return false }
        return searchSource == .partialCache || searchSource == .savedFallback
    }

    /// The featured chart with today's pick removed so the hero and the numbered
    /// list never show the same book twice.
    var chartBooks: [LibriVoxBook] {
        guard let pick = todaysPick else { return featuredBooks }
        return featuredBooks.filter { $0.id != pick.id }
    }

    /// True while the curated-classics preload is fetching, before anything is on screen.
    var isPreloadingFeatured: Bool = false

    // MARK: - Filter state

    var selectedLanguage: String? = nil
    var selectedGenre: String? = nil
    var selectedDuration: DurationFilter? = nil
    var availableLanguages: [String] = []
    var availableGenres: [String] = []

    var hasActiveFilters: Bool {
        selectedLanguage != nil || selectedGenre != nil || selectedDuration != nil
    }

    /// Static fallbacks so the filter menus are never empty — shown until synced rows
    /// carry real genre/language data. Names match LibriVox genre strings (verified
    /// against the feed's `genre` parameter).
    static let fallbackGenres: [String] = [
        "General Fiction", "Historical Fiction", "Science Fiction", "Fantastic Fiction",
        "Detective Fiction", "Romance", "Short Stories", "Poetry", "Children's Fiction",
        "Action & Adventure", "Humorous Fiction", "Plays", "Literary Fiction",
        "War & Military Fiction", "Westerns", "History", "Biography & Autobiography",
        "Philosophy", "Religion", "Science", "Travel & Geography"
    ]

    static let fallbackLanguages: [String] = [
        "English", "German", "French", "Spanish", "Italian", "Dutch", "Portuguese", "Russian"
    ]

    /// What the filter menus show. Catalog-derived lists once the catalog is complete;
    /// while it is still downloading, the static list plus anything already seen, so a
    /// partial cache never shrinks the menus. Genres capped to the 40 most common.
    var genreOptions: [String] {
        guard !isLocalSearchReady else {
            return availableGenres.isEmpty ? Self.fallbackGenres : Array(availableGenres.prefix(40))
        }
        return Self.merged(Self.fallbackGenres, availableGenres, cap: 40)
    }

    var languageOptions: [String] {
        guard !isLocalSearchReady else {
            return availableLanguages.isEmpty ? Self.fallbackLanguages : availableLanguages
        }
        return Self.merged(Self.fallbackLanguages, availableLanguages, cap: nil)
    }

    private static func merged(_ base: [String], _ extra: [String], cap: Int?) -> [String] {
        var seen = Set(base)
        var result = base
        for value in extra where seen.insert(value).inserted {
            if let cap, result.count >= cap { break }
            result.append(value)
        }
        return result
    }

    // MARK: - Sample playback URL cache

    var cachedFirstTrackURLs: [String: URL] = [:]

    func fetchFirstTrackURL(for book: LibriVoxBook) async -> URL? {
        if let cached = cachedFirstTrackURLs[book.id] { return cached }
        // Try cached tracks on the book first
        if let cachedTracks = book.cachedTracks, let first = cachedTracks.first,
           let url = URL(string: first.listenURL) {
            cachedFirstTrackURLs[book.id] = url
            return url
        }
        guard let tracks = try? await LibriVoxAPIClient.fetchTracks(projectID: book.id),
              let first = tracks.first,
              let url = URL(string: first.listenURL) else { return nil }
        cachedFirstTrackURLs[book.id] = url
        return url
    }

    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var syncTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var catalogPresentationTask: Task<Void, Never>?
    private var lastCatalogPresentationRefresh: Date = .distantPast

    /// Non-blocking background preparation/update indicator.
    var isLoadingFullCatalog: Bool {
        if case .syncing = syncState { return true }
        return false
    }

    /// True while the very first full catalog download is running (no data cached yet) — used to
    /// phrase the background banner as a first build vs. an incremental refresh. Captured at
    /// sync start: the per-page count updates would otherwise flip the banner text mid-sync.
    private(set) var isFirstFullSync: Bool = false

    /// Network is unreachable and there is nothing cached at all — no full catalog and not
    /// even the curated classics — so the tab has nothing to show.
    var isOfflineWithNoData: Bool {
        if case .failed(_, let offline) = syncState {
            return offline && LibriVoxCatalogSync.syncedBookCount == 0 && featuredBooks.isEmpty
        }
        return false
    }

    /// Network is unreachable but something is cached (full catalog and/or the classics) so
    /// the user still has books to browse.
    var isOfflineWithCachedData: Bool {
        if case .failed(_, let offline) = syncState {
            return offline && (LibriVoxCatalogSync.syncedBookCount > 0 || !featuredBooks.isEmpty)
        }
        return false
    }

    /// A non-connectivity load failure (server error, unreadable response) with nothing
    /// cached and no classics to fall back on — shown as a retriable error state.
    var loadFailedWithNoData: Bool {
        if case .failed(_, let offline) = syncState {
            return !offline
                && LibriVoxCatalogSync.syncedBookCount == 0
                && featuredBooks.isEmpty
        }
        return false
    }

    /// The friendly message from the most recent failure, if any.
    var failureMessage: String? {
        if case .failed(let message, _) = syncState { return message }
        return nil
    }

    // MARK: - Background store

    private var store: LibriVoxCatalogStore?
    private weak var storeContainer: ModelContainer?

    /// The background `@ModelActor` for `modelContext`'s container. Every catalog-sized
    /// fetch or write goes through it so the main actor only resolves displayed rows.
    func catalogStore(for modelContext: ModelContext) async -> LibriVoxCatalogStore {
        let container = modelContext.container
        if let store, storeContainer === container { return store }
        let made = await LibriVoxCatalogStore.make(container: container)
        if let store, storeContainer === container { return store }
        store = made
        storeContainer = container
        return made
    }

    /// Resolves ids on the main context, preserving order.
    private func books(withIDs ids: [String], modelContext: ModelContext) -> [LibriVoxBook] {
        guard !ids.isEmpty else { return [] }
        let predicate = #Predicate<LibriVoxBook> { ids.contains($0.id) }
        guard let rows = try? modelContext.fetch(FetchDescriptor(predicate: predicate)) else { return [] }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    // MARK: - Search

    func catalogBook(id: String, modelContext: ModelContext) -> LibriVoxBook? {
        var descriptor = FetchDescriptor<LibriVoxBook>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func onQueryChanged(_ query: String, modelContext: ModelContext) {
        searchTask?.cancel()
        // Invalidate old results immediately, including during the debounce delay.
        searchGeneration += 1
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || hasActiveFilters else {
            searchResults = []
            searchSource = nil
            searchFailureMessage = nil
            isSearchingLibriVox = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performSearch(query: query, modelContext: modelContext)
        }
    }

    /// Re-runs the current search after a filter change.
    func triggerSearch(modelContext: ModelContext) {
        onQueryChanged(searchQuery, modelContext: modelContext)
    }

    /// Search and filters are always available. With the complete catalog everything is
    /// local. While the catalog is still downloading, text and genre go to the live feed
    /// (its `title`/`author`/`genre` parameters), are narrowed by the remaining filters,
    /// and are merged with matching cached books; language/length-only browsing and
    /// offline use filter the cached subset and are flagged as partial.
    func performSearch(query: String, modelContext: ModelContext) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || hasActiveFilters else {
            searchResults = []
            searchSource = nil
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        searchFailureMessage = nil
        let filters = LibriVoxCatalogQuery(
            text: trimmed,
            language: selectedLanguage,
            genre: selectedGenre,
            duration: selectedDuration
        )
        let store = await catalogStore(for: modelContext)

        if isLocalSearchReady {
            isSearchingLibriVox = false
            await showCachedResults(filters, store: store, modelContext: modelContext,
                                    source: .local, generation: generation)
            return
        }

        guard filters.hasText || filters.genre != nil else {
            isSearchingLibriVox = false
            await showCachedResults(filters, store: store, modelContext: modelContext,
                                    source: .partialCache, generation: generation)
            return
        }

        isSearchingLibriVox = true
        defer { if generation == searchGeneration { isSearchingLibriVox = false } }
        do {
            let apiBooks: [LibriVoxAPIBook]
            if filters.hasText {
                apiBooks = try await remoteSearch.search(query: trimmed)
            } else {
                apiBooks = try await remoteSearch.browse(genre: filters.genre ?? "")
            }
            try Task.checkCancellation()
            let remote = apiBooks.filter { filters.matches($0) }
            try await store.upsert(remote)
            let cachedIDs = try await store.search(filters)
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }

            var ids = remote.map(\.id)
            var seen = Set(ids)
            for id in cachedIDs where seen.insert(id).inserted { ids.append(id) }
            searchResults = books(withIDs: ids, modelContext: modelContext)
            searchSource = .librivox
        } catch {
            if error is CancellationError || Task.isCancelled || generation != searchGeneration { return }
            let offline = isNetworkUnavailable(error)
            await showCachedResults(filters, store: store, modelContext: modelContext,
                                    source: offline ? .savedFallback : .partialCache,
                                    generation: generation)
            if !offline, searchResults.isEmpty, generation == searchGeneration {
                searchSource = nil
                searchFailureMessage = error.localizedDescription
            }
        }
    }

    private func showCachedResults(
        _ filters: LibriVoxCatalogQuery,
        store: LibriVoxCatalogStore,
        modelContext: ModelContext,
        source: SearchSource,
        generation: Int
    ) async {
        let ids = (try? await store.search(filters)) ?? []
        guard generation == searchGeneration, !Task.isCancelled else { return }
        searchResults = books(withIDs: ids, modelContext: modelContext)
        searchSource = source
    }

    func refreshBookIfStale(
        _ book: LibriVoxBook,
        modelContext: ModelContext,
        now: Date = .now
    ) async {
        guard now.timeIntervalSince(book.lastSyncedAt) >= 86_400 else { return }
        do {
            guard let refreshed = try await remoteSearch.fetchBook(id: book.id) else { return }
            try LibriVoxCatalogSync.seed([refreshed], into: modelContext)
        } catch {
            // Detail stays usable with cached metadata when LibriVox is unavailable.
        }
    }

    // MARK: - Filters

    /// Catalog size the filter lists were last computed from — recompute when the data
    /// grows (sync progress, refresh) but skip the aggregation on every tab visit.
    private var filtersComputedForCount: Int = -1

    func loadAvailableFilters(modelContext: ModelContext) async {
        let count = (try? modelContext.fetchCount(FetchDescriptor<LibriVoxBook>())) ?? 0
        guard count > 0, count != filtersComputedForCount else { return }
        let store = await catalogStore(for: modelContext)
        guard let options = try? await store.filterOptions() else { return }
        filtersComputedForCount = count
        availableLanguages = options.languages
        availableGenres = options.genres
    }

    // MARK: - Featured Books

    static let featuredTitles: [String] = [
        "The Art of War",
        "The Adventures of Sherlock Holmes",
        "Pride and Prejudice",
        "Jane Eyre",
        "Adventures of Huckleberry Finn",
        "Frankenstein",
        "The Picture of Dorian Gray",
        "The Scarlet Pimpernel",
        "Dracula",
        "The Count of Monte Cristo",
        "Treasure Island",
        "The War of the Worlds",
        "The Invisible Man",
        "The Wonderful Wizard of Oz",
        "Gulliver's Travels",
        "Our Mutual Friend",
        "A Tale of Two Cities",
        "The Woman in White",
        "Crime and Punishment",
        "Anna Karenina",
        "Black Beauty",
        "Persuasion",
        "Barnaby Rudge",
        "Three Men in a Boat",
        "Twenty Years After",
        "Incidents in the Life of a Slave Girl",
        "The Mysterious Affair at Styles",
        "Common Sense",
        "The Dhammapada",
        "The Iliad",
        "The Odyssey"
    ]

    static let featuredBooksTarget = 5

    /// Curated LibriVox project IDs for well-known classics, used to preload a handful
    /// of featured books on a fresh install *before* the full catalog sync finishes.
    /// More than `featuredBooksTarget` so the shown set can still be shuffled for variety.
    /// IDs verified against the live LibriVox feed API (librivox.org/api/feed/audiobooks).
    static let curatedClassicIDs: [String] = [
        "314", // Adventures of Sherlock Holmes — Arthur Conan Doyle
        "253", // Pride and Prejudice — Jane Austen
        "133", // Jane Eyre — Charlotte Brontë
        "381", // Frankenstein, or The Modern Prometheus — Mary Shelley
        "271", // Dracula — Bram Stoker
        "449", // Treasure Island — Robert Louis Stevenson
        "436", // War of the Worlds — H. G. Wells
        "510", // Tale of Two Cities — Charles Dickens
    ]

    private var preloadTask: Task<Void, Never>?

    /// Deterministic daily hero: same curated classic for everyone on a given day,
    /// rotating through the verified ID list by day-of-year. Resolved from the local
    /// cache only — the preload seeds these rows, so no extra network is needed.
    @MainActor
    func loadTodaysPick(modelContext: ModelContext) {
        let ids = Self.curatedClassicIDs
        guard !ids.isEmpty else { return }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        let id = ids[dayOfYear % ids.count]
        guard todaysPick?.id != id else { return }
        let predicate = #Predicate<LibriVoxBook> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        if let book = try? modelContext.fetch(descriptor).first {
            todaysPick = book
        }
    }

    /// Preloads a handful of curated classics so the Shelves tab shows content
    /// immediately on a fresh install, before the multi-minute full catalog sync.
    /// Idempotent and offline-safe: skips work if featured books are already shown
    /// or the curated rows already exist locally, and silently degrades (no featured)
    /// if the network is unavailable.
    @MainActor
    func preloadFeaturedClassics(modelContext: ModelContext) {
        guard featuredBooks.isEmpty, preloadTask == nil else { return }
        preloadTask = Task { [weak self] in
            await self?.performPreload(modelContext: modelContext)
            self?.preloadTask = nil
        }
    }

    @MainActor
    private func performPreload(modelContext: ModelContext) async {
        guard featuredBooks.isEmpty, !isPreloadingFeatured else { return }
        isPreloadingFeatured = true
        defer { isPreloadingFeatured = false }
        let ids = Self.curatedClassicIDs

        // Already present locally (relaunch / partial-or-full sync) — no network needed.
        // Capture the array (not a Set) — `Array.contains` is the form SwiftData predicates support.
        let existingPredicate = #Predicate<LibriVoxBook> { ids.contains($0.id) }
        if let existing = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate)),
           existing.count >= Self.featuredBooksTarget {
            featuredBooks = Array(existing.shuffled().prefix(Self.featuredBooksTarget))
            loadTodaysPick(modelContext: modelContext)
            return
        }

        // Fetch curated metadata and seed it into the store. On failure (offline),
        // degrade gracefully: leave featuredBooks empty.
        guard let apiBooks = try? await LibriVoxAPIClient.fetchBooks(ids: ids),
              !apiBooks.isEmpty else { return }
        try? LibriVoxCatalogSync.seed(apiBooks, into: modelContext)

        // Re-fetch the now-persisted rows so featuredBooks holds context-managed
        // instances rather than the throwaway decoded API objects.
        guard let rows = try? modelContext.fetch(FetchDescriptor(predicate: existingPredicate)),
              !rows.isEmpty else { return }
        featuredBooks = Array(rows.shuffled().prefix(Self.featuredBooksTarget))
        loadTodaysPick(modelContext: modelContext)
    }

    @MainActor
    func loadFeaturedBooks(modelContext: ModelContext) async {
        guard featuredBooks.isEmpty else { return }
        // Title scans over the 20k-row catalog run on the background store; only the
        // handful of winners are resolved on the main context.
        let store = await catalogStore(for: modelContext)
        guard let ids = try? await store.firstIDs(matchingTitles: Self.featuredTitles.shuffled(),
                                                  limit: Self.featuredBooksTarget),
              featuredBooks.isEmpty else { return }
        featuredBooks = books(withIDs: ids, modelContext: modelContext)
    }

    // MARK: - Sync

    /// Passes started since launch — lets tests prove foreground/visit churn never
    /// starts a duplicate.
    private(set) var syncRunsStarted = 0
    var isSyncInFlight: Bool { syncTask != nil }

    private var pauseFlag: LibriVoxSyncPauseFlag?
    private var resumeAfterPause = false
    private(set) var isAppInBackground = false
    private var syncContext: ModelContext?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// Books written by the most recent pass, for the "N new books added" note.
    private var lastRunProcessed = 0

    func triggerSyncIfNeeded(modelContext: ModelContext) {
        #if DEBUG
        if E2EFixtures.enabled {
            Task { [weak self] in
                await self?.loadFeaturedBooks(modelContext: modelContext)
                self?.loadTodaysPick(modelContext: modelContext)
                await self?.loadAvailableFilters(modelContext: modelContext)
                if !NetworkMonitor.shared.isConnected {
                    self?.syncState = .failed("You're offline.", isOffline: true)
                }
            }
            return
        }
        #endif
        syncContext = modelContext
        observeAppLifecycleIfNeeded()
        guard !isAppInBackground else { return }
        guard syncTask == nil else {
            // A sync is already in flight; just make sure the curated classics are populated.
            if featuredBooks.isEmpty { preloadFeaturedClassics(modelContext: modelContext) }
            return
        }
        guard isSyncDueProvider() else {
            Task { [weak self] in
                if self?.featuredBooks.isEmpty == true {
                    await self?.loadFeaturedBooks(modelContext: modelContext)
                }
                self?.loadTodaysPick(modelContext: modelContext)
                await self?.loadAvailableFilters(modelContext: modelContext)
            }
            return
        }
        guard isConnectedProvider() else {
            // Network gating: don't start a pass that can only fail. Cached classics and
            // the partial catalog stay browsable; reconnecting or Retry resumes the cursor.
            Task { [weak self] in
                await self?.performPreload(modelContext: modelContext)
                self?.loadTodaysPick(modelContext: modelContext)
                await self?.loadAvailableFilters(modelContext: modelContext)
                self?.syncState = .failed("No internet connection", isOffline: true)
            }
            return
        }
        startSync(modelContext: modelContext)
    }

    func forceRefresh(modelContext: ModelContext) {
        syncContext = modelContext
        observeAppLifecycleIfNeeded()
        availableLanguages = []
        availableGenres = []
        filtersComputedForCount = -1
        guard syncTask == nil else { return }
        startSync(modelContext: modelContext)
    }

    private func startSync(modelContext: ModelContext) {
        let flag = LibriVoxSyncPauseFlag()
        pauseFlag = flag
        resumeAfterPause = false
        lastCatalogPresentationRefresh = .distantPast
        syncRunsStarted += 1
        syncTask = Task(priority: .utility) { [weak self] in
            // Curated content arrives first on a fresh install (or after an offline retry).
            // Remote search remains usable throughout; the full index is an optimization.
            if self?.isLocalSearchReady == false || self?.featuredBooks.isEmpty == true {
                await self?.performPreload(modelContext: modelContext)
            }
            await self?.performSync(modelContext: modelContext, pauseFlag: flag)
            self?.syncDidFinish()
        }
    }

    private func performSync(modelContext: ModelContext, pauseFlag: LibriVoxSyncPauseFlag) async {
        if pauseFlag.isRaised {
            syncState = .paused(saved: LibriVoxCatalogSync.syncedBookCount)
            return
        }
        let wasReady = isLocalSearchReady
        isFirstFullSync = !wasReady
        lastRunProcessed = 0
        syncState = .syncing(fetched: wasReady ? 0 : LibriVoxCatalogSync.syncedBookCount)
        do {
            let store = await catalogStore(for: modelContext)
            let firstFull = isFirstFullSync
            let outcome = try await syncRunner(store, pauseFlag) { [weak self] progress in
                guard let self else { return }
                self.lastRunProcessed = progress.processedThisRun
                // Only publish while still syncing: a late page must not overwrite `.paused`.
                if case .syncing = self.syncState {
                    self.syncState = .syncing(fetched: firstFull ? progress.savedCount : progress.processedThisRun)
                }
                self.refreshCatalogPresentationAfterPage(modelContext: modelContext)
            }
            if outcome == .paused {
                syncState = .paused(saved: LibriVoxCatalogSync.syncedBookCount)
                return
            }
            syncState = .done
            await loadAvailableFilters(modelContext: modelContext)
            await loadFeaturedBooks(modelContext: modelContext)
            loadTodaysPick(modelContext: modelContext)
            if !wasReady && isLocalSearchReady {
                showTemporaryUpdateMessage("Offline search ready")
            } else if lastRunProcessed > 0 {
                showTemporaryUpdateMessage("\(lastRunProcessed.formatted()) new book\(lastRunProcessed == 1 ? "" : "s") added")
            }
            // Seamless hand-off: re-run the active search against the now-complete catalog.
            let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty || hasActiveFilters {
                await performSearch(query: searchQuery, modelContext: modelContext)
            }
        } catch {
            if pauseFlag.isRaised || Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                syncState = .paused(saved: LibriVoxCatalogSync.syncedBookCount)
                return
            }
            let offline = isNetworkUnavailable(error)
            let message = offline
                ? "No internet connection"
                : error.localizedDescription
            syncState = .failed(message, isOffline: offline)
        }
    }

    private func syncDidFinish() {
        syncTask = nil
        pauseFlag = nil
        endBackgroundTaskIfNeeded()
        if resumeAfterPause, !isAppInBackground, let context = syncContext {
            resumeAfterPause = false
            triggerSyncIfNeeded(modelContext: context)
        }
    }

    /// Language/length-only filters use the growing cache because the feed cannot query
    /// those dimensions. Refresh that visible subset and the menus as pages arrive,
    /// without issuing another remote request or scanning the whole catalog per page.
    private func refreshCatalogPresentationAfterPage(modelContext: ModelContext) {
        guard !isAppInBackground, catalogPresentationTask == nil,
              Date().timeIntervalSince(lastCatalogPresentationRefresh) >= 2 else { return }
        lastCatalogPresentationRefresh = .now
        catalogPresentationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.catalogPresentationTask = nil }
            await self.loadAvailableFilters(modelContext: modelContext)
            guard self.searchSource == .partialCache || self.searchSource == .savedFallback else { return }
            let generation = self.searchGeneration
            let filters = LibriVoxCatalogQuery(
                text: self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                language: self.selectedLanguage, genre: self.selectedGenre,
                duration: self.selectedDuration
            )
            guard filters.hasText || self.hasActiveFilters else { return }
            let source = self.searchSource ?? .partialCache
            let store = await self.catalogStore(for: modelContext)
            await self.showCachedResults(filters, store: store, modelContext: modelContext,
                                         source: source, generation: generation)
        }
    }

    // MARK: - App lifecycle

    /// Observed here rather than through the view's `scenePhase`, because the sync keeps
    /// running while another tab is on screen.
    private func observeAppLifecycleIfNeeded() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.appDidEnterBackground() }
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.appWillEnterForeground() }
            },
        ]
    }

    /// Asks the in-flight pass to stop after the page it is on. A short background task
    /// keeps the process alive until that page is saved; if iOS expires it first, the
    /// pass is cancelled outright (the cursor still points at the last committed page).
    func appDidEnterBackground() {
        isAppInBackground = true
        resumeAfterPause = false
        guard let task = syncTask, let flag = pauseFlag else { return }
        flag.raise()
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LibriVox catalog page") { [weak self] in
            MainActor.assumeIsolated {
                task.cancel()
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    /// Resumes from the persisted cursor. Never starts a second pass: if the paused one is
    /// still winding down, it restarts once that finishes.
    func appWillEnterForeground() {
        isAppInBackground = false
        guard let context = syncContext else { return }
        if syncTask != nil {
            resumeAfterPause = pauseFlag?.isRaised == true
            return
        }
        triggerSyncIfNeeded(modelContext: context)
    }

    /// Connectivity came back: resume a pass that stopped for lack of network.
    func networkBecameAvailable() {
        guard let context = syncContext, syncTask == nil else { return }
        if case .failed = syncState {
            triggerSyncIfNeeded(modelContext: context)
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func showTemporaryUpdateMessage(_ message: String) {
        statusTask?.cancel()
        backgroundUpdateMessage = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.backgroundUpdateMessage = nil
        }
    }

    private func isNetworkUnavailable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
