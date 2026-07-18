//
//  BrowseLibriVoxViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

enum DurationFilter: String, CaseIterable, Identifiable {
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
        case librivox
        case local
        case savedFallback
    }

    enum SyncState {
        case idle
        case syncing(fetched: Int)
        case done
        case failed(String, isOffline: Bool)
    }

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

    init(
        remoteSearch: (any LibriVoxRemoteSearching)? = nil,
        isLocalSearchReady: (() -> Bool)? = nil
    ) {
        self.remoteSearch = remoteSearch ?? LiveLibriVoxRemoteSearch()
        self.isLocalSearchReadyProvider = isLocalSearchReady ?? { LibriVoxCatalogSync.isLocalSearchReady }
    }

    var isLocalSearchReady: Bool { isLocalSearchReadyProvider() }
    var filtersAvailable: Bool { isLocalSearchReady }

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
    /// carry real genre/language data (rows cached before the genres API field was added
    /// only backfill on a refresh or reset). Names match LibriVox genre strings.
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

    /// What the filter menus show: catalog-derived lists when available, static fallbacks
    /// otherwise. Genres capped to the most common 40 — the full taxonomy is 100+ entries,
    /// too long for a usable Menu.
    var genreOptions: [String] {
        availableGenres.isEmpty ? Self.fallbackGenres : Array(availableGenres.prefix(40))
    }

    var languageOptions: [String] {
        availableLanguages.isEmpty ? Self.fallbackLanguages : availableLanguages
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
    private var syncTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
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

    @MainActor
    func performSearch(query: String, modelContext: ModelContext) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || (filtersAvailable && hasActiveFilters) else {
            searchResults = []
            searchSource = nil
            return
        }

        searchFailureMessage = nil
        if isLocalSearchReady {
            isSearchingLibriVox = false
            performLocalSearch(query: trimmed, modelContext: modelContext, source: .local)
            return
        }

        guard !trimmed.isEmpty else {
            searchResults = []
            searchSource = nil
            return
        }

        isSearchingLibriVox = true
        defer { isSearchingLibriVox = false }
        do {
            let apiBooks = try await remoteSearch.search(query: trimmed)
            try Task.checkCancellation()
            try LibriVoxCatalogSync.seed(apiBooks, into: modelContext)
            try Task.checkCancellation()

            let ids = apiBooks.map(\.id)
            let predicate = #Predicate<LibriVoxBook> { ids.contains($0.id) }
            let stored = try modelContext.fetch(FetchDescriptor(predicate: predicate))
            let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            searchResults = ids.compactMap { byID[$0] }
            searchSource = .librivox
        } catch is CancellationError {
            return
        } catch {
            if isNetworkUnavailable(error) {
                performLocalSearch(query: trimmed, modelContext: modelContext, source: .savedFallback)
            } else {
                searchResults = []
                searchSource = nil
                searchFailureMessage = error.localizedDescription
            }
        }
    }

    private func performLocalSearch(
        query trimmed: String,
        modelContext: ModelContext,
        source: SearchSource
    ) {
        let lang = selectedLanguage
        do {
            var raw: [LibriVoxBook]
            let hasText = !trimmed.isEmpty

            if hasText, let lang {
                // Text + language — both pushed to DB predicate
                let predicate = #Predicate<LibriVoxBook> { book in
                    (book.title.localizedStandardContains(trimmed) ||
                     book.authorDisplay.localizedStandardContains(trimmed) ||
                     book.bookDescription.localizedStandardContains(trimmed)) &&
                    book.language == lang
                }
                var d = FetchDescriptor(predicate: predicate)
                d.fetchLimit = 200
                raw = try modelContext.fetch(d)
            } else if hasText {
                // Text only
                let predicate = #Predicate<LibriVoxBook> { book in
                    book.title.localizedStandardContains(trimmed) ||
                    book.authorDisplay.localizedStandardContains(trimmed) ||
                    book.bookDescription.localizedStandardContains(trimmed)
                }
                var d = FetchDescriptor(predicate: predicate)
                d.fetchLimit = 150
                raw = try modelContext.fetch(d)
            } else {
                // Filter-only browse. Language pushes to the DB predicate; genre (stored as
                // a JSON string) and duration buckets can't, so fetch the whole (language-
                // scoped) catalog and filter in memory — same cost as the filter-list
                // computation, and a capped pre-filter fetch would miss most matches.
                let d: FetchDescriptor<LibriVoxBook>
                if let lang {
                    d = FetchDescriptor(predicate: #Predicate { $0.language == lang })
                } else {
                    d = FetchDescriptor<LibriVoxBook>()
                }
                raw = try modelContext.fetch(d)
            }

            // In-memory: genre (stored as JSON string, not queryable via DB predicate)
            if let genre = selectedGenre {
                raw = raw.filter { $0.genres.contains(genre) }
            }
            // In-memory: duration bucket
            if let dur = selectedDuration {
                raw = raw.filter { dur.matches(seconds: $0.totalTimeSecs) }
            }

            // Sort
            if hasText {
                let q = trimmed.lowercased()
                searchResults = raw.sorted { rankScore($0, query: q) < rankScore($1, query: q) }
            } else {
                searchResults = Array(raw.sorted { $0.title < $1.title }.prefix(500))
            }
            searchSource = source
        } catch {
            searchResults = []
            searchSource = nil
        }
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

    private func rankScore(_ book: LibriVoxBook, query: String) -> Int {
        let t = book.title.lowercased()
        let a = book.authorDisplay.lowercased()
        if t.hasPrefix(query) { return 0 }
        if t.contains(query) { return 1 }
        if a.contains(query) { return 2 }
        return 3
    }

    // MARK: - Filters

    /// Catalog size the filter lists were last computed from — recompute when the data
    /// grows (sync progress, refresh) but skip the 20k-row fetch on every tab visit.
    private var filtersComputedForCount: Int = -1

    @MainActor
    func loadAvailableFilters(modelContext: ModelContext) async {
        let count = (try? modelContext.fetchCount(FetchDescriptor<LibriVoxBook>())) ?? 0
        guard count > 0, count != filtersComputedForCount else { return }
        guard let books = try? modelContext.fetch(FetchDescriptor<LibriVoxBook>()) else { return }
        filtersComputedForCount = count

        var langs = Array(Set(books.map(\.language).filter { !$0.isEmpty })).sorted()
        if let idx = langs.firstIndex(of: "English") {
            langs.remove(at: idx)
            langs.insert("English", at: 0)
        }
        availableLanguages = langs

        var counts: [String: Int] = [:]
        for g in books.flatMap(\.genres) { counts[g, default: 0] += 1 }
        availableGenres = counts.sorted { $0.value > $1.value }.map(\.key)
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

    /// Preloads a handful of curated classics so the Free Books tab shows content
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
        let shuffled = Self.featuredTitles.shuffled()
        var found: [LibriVoxBook] = []
        var seenIds = Set<String>()
        for title in shuffled {
            if found.count >= Self.featuredBooksTarget { break }
            let t = title
            let predicate = #Predicate<LibriVoxBook> { book in
                book.title.localizedStandardContains(t)
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = 1
            if let book = try? modelContext.fetch(descriptor).first,
               seenIds.insert(book.id).inserted {
                found.append(book)
            }
        }
        featuredBooks = found
    }

    // MARK: - Sync

    @MainActor
    func triggerSyncIfNeeded(modelContext: ModelContext) {
        guard syncTask == nil else {
            // A sync is already in flight; just make sure the curated classics are populated.
            if featuredBooks.isEmpty { preloadFeaturedClassics(modelContext: modelContext) }
            return
        }
        guard LibriVoxCatalogSync.isSyncDue else {
            Task { [weak self] in
                if self?.featuredBooks.isEmpty == true {
                    await self?.loadFeaturedBooks(modelContext: modelContext)
                }
                self?.loadTodaysPick(modelContext: modelContext)
                await self?.loadAvailableFilters(modelContext: modelContext)
            }
            return
        }

        syncTask = Task(priority: .utility) { [weak self] in
            // Curated content arrives first on a fresh install. Remote search remains usable
            // throughout; the full local index is a background optimization.
            if self?.isLocalSearchReady == false {
                await self?.performPreload(modelContext: modelContext)
            }
            await self?.performSync(modelContext: modelContext)
        }
    }

    @MainActor
    func forceRefresh(modelContext: ModelContext) {
        availableLanguages = []
        availableGenres = []
        filtersComputedForCount = -1
        syncTask = Task { [weak self] in
            // If we still have no classics (retry from an offline/error state), grab them first
            // so the tab shows content quickly before the full re-sync runs.
            if self?.featuredBooks.isEmpty == true {
                await self?.performPreload(modelContext: modelContext)
            }
            await self?.performSync(modelContext: modelContext)
        }
    }

    @MainActor
    private func performSync(modelContext: ModelContext) async {
        let wasReady = isLocalSearchReady
        isFirstFullSync = !wasReady
        var lastProgress = 0
        syncState = .syncing(fetched: 0)
        do {
            try await LibriVoxCatalogSync.syncIfNeeded(modelContext: modelContext) { [weak self] fetched in
                lastProgress = fetched
                self?.syncState = .syncing(fetched: fetched)
            }
            syncState = .done
            await loadAvailableFilters(modelContext: modelContext)
            await loadFeaturedBooks(modelContext: modelContext)
            loadTodaysPick(modelContext: modelContext)
            if !wasReady && isLocalSearchReady {
                showTemporaryUpdateMessage("Offline search ready")
            } else if lastProgress > 0 {
                showTemporaryUpdateMessage("\(lastProgress.formatted()) new book\(lastProgress == 1 ? "" : "s") added")
            }
            let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty || hasActiveFilters {
                await performSearch(query: searchQuery, modelContext: modelContext)
            }
        } catch {
            let offline = isNetworkUnavailable(error)
            let message = offline
                ? "No internet connection"
                : error.localizedDescription
            syncState = .failed(message, isOffline: offline)
        }
        syncTask = nil
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
