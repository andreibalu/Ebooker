//
//  BrowseLibriVoxViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

struct ActiveLibriVoxDownload: Identifiable {
    let id: String // book.id
    let book: LibriVoxBook
    var completed: Int
    var total: Int

    var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

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

@Observable
final class BrowseLibriVoxViewModel {
    enum SyncState {
        case idle
        case syncing(fetched: Int)
        case done
        case failed(String, isOffline: Bool)
    }

    var searchQuery: String = ""
    var searchResults: [LibriVoxBook] = []
    var syncState: SyncState = .idle
    var activeDownloads: [String: ActiveLibriVoxDownload] = [:]
    var featuredBooks: [LibriVoxBook] = []

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

    var sortedActiveDownloads: [ActiveLibriVoxDownload] {
        activeDownloads.values.sorted { $0.book.title < $1.book.title }
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
    private var cancelHandlers: [String: () -> Void] = [:]

    // MARK: - Download tracking

    func registerDownload(book: LibriVoxBook, total: Int, cancelHandler: @escaping () -> Void = {}) {
        activeDownloads[book.id] = ActiveLibriVoxDownload(id: book.id, book: book, completed: 0, total: total)
        cancelHandlers[book.id] = cancelHandler
    }

    func updateDownloadProgress(bookId: String, completed: Int, total: Int) {
        activeDownloads[bookId]?.completed = completed
        activeDownloads[bookId]?.total = total
    }

    func completeDownload(bookId: String) {
        activeDownloads.removeValue(forKey: bookId)
        cancelHandlers.removeValue(forKey: bookId)
    }

    func cancelOrFailDownload(bookId: String) {
        activeDownloads.removeValue(forKey: bookId)
        cancelHandlers.removeValue(forKey: bookId)
    }

    func cancelDownload(bookId: String) {
        cancelHandlers[bookId]?()
        cancelHandlers.removeValue(forKey: bookId)
    }

    var lastSyncDescription: String {
        guard let date = LibriVoxCatalogSync.lastSyncDate else { return "Never synced" }
        return "Updated \(TimeFormatter.relativeDateString(for: date)) · Books provided by Librivox"
    }

    var catalogCount: Int { LibriVoxCatalogSync.syncedBookCount }

    /// Blocking overlay: there is nothing on screen yet (no classics, no search results, not
    /// offline) and we are actively loading. As soon as the curated classics arrive this turns
    /// false and the full catalog continues loading behind a non-blocking inline banner.
    var isInitialLoading: Bool {
        guard featuredBooks.isEmpty,
              searchResults.isEmpty,
              searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isOfflineWithNoData else { return false }
        if isPreloadingFeatured { return true }
        if case .syncing = syncState { return LibriVoxCatalogSync.syncedBookCount == 0 }
        return false
    }

    /// Non-blocking: the full catalog is streaming in while classics (or cached data) are visible.
    var isLoadingFullCatalog: Bool {
        guard !isInitialLoading else { return false }
        if case .syncing = syncState { return true }
        return false
    }

    /// True while the very first full catalog download is running (no data cached yet) — used to
    /// phrase the background banner as a first build vs. an incremental refresh.
    var isFirstFullSync: Bool {
        LibriVoxCatalogSync.syncedBookCount == 0
    }

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

    func onQueryChanged(_ query: String, modelContext: ModelContext) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || hasActiveFilters else {
            searchResults = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runSearch(query: query, modelContext: modelContext)
        }
    }

    /// Re-runs the current search after a filter change.
    func triggerSearch(modelContext: ModelContext) {
        onQueryChanged(searchQuery, modelContext: modelContext)
    }

    @MainActor
    private func runSearch(query: String, modelContext: ModelContext) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = selectedLanguage
        guard !trimmed.isEmpty || lang != nil || selectedGenre != nil || selectedDuration != nil else {
            searchResults = []
            return
        }
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
            } else if let lang {
                // Language filter only
                let predicate = #Predicate<LibriVoxBook> { book in book.language == lang }
                var d = FetchDescriptor(predicate: predicate)
                d.fetchLimit = 500
                raw = try modelContext.fetch(d)
            } else {
                // Genre / duration browse — fetch a capped sample
                var d = FetchDescriptor<LibriVoxBook>()
                d.fetchLimit = 500
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
                searchResults = raw.sorted { $0.title < $1.title }
            }
        } catch {
            searchResults = []
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

    @MainActor
    func loadAvailableFilters(modelContext: ModelContext) async {
        guard LibriVoxCatalogSync.syncedBookCount > 0 else { return }
        guard availableLanguages.isEmpty || availableGenres.isEmpty else { return }
        guard let books = try? modelContext.fetch(FetchDescriptor<LibriVoxBook>()) else { return }

        if availableLanguages.isEmpty {
            var langs = Array(Set(books.map(\.language).filter { !$0.isEmpty })).sorted()
            if let idx = langs.firstIndex(of: "English") {
                langs.remove(at: idx)
                langs.insert("English", at: 0)
            }
            availableLanguages = langs
        }

        if availableGenres.isEmpty {
            var counts: [String: Int] = [:]
            for g in books.flatMap(\.genres) { counts[g, default: 0] += 1 }
            availableGenres = counts.sorted { $0.value > $1.value }.map(\.key)
        }
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
        switch syncState {
        case .idle, .failed:
            syncTask = Task { [weak self] in
                // 1. Curated classics first — fast and shown the instant they arrive, so the tab
                //    has content immediately after onboarding.
                await self?.performPreload(modelContext: modelContext)
                // 2. Only then start the multi-minute full catalog sync, in the background.
                await self?.performSync(modelContext: modelContext, force: false)
            }
        default:
            if LibriVoxCatalogSync.syncedBookCount > 0 && featuredBooks.isEmpty {
                Task { [weak self] in await self?.loadFeaturedBooks(modelContext: modelContext) }
            }
        }
    }

    @MainActor
    func forceRefresh(modelContext: ModelContext) {
        syncTask?.cancel()
        availableLanguages = []
        availableGenres = []
        syncTask = Task { [weak self] in
            // If we still have no classics (retry from an offline/error state), grab them first
            // so the tab shows content quickly before the full re-sync runs.
            if self?.featuredBooks.isEmpty == true {
                await self?.performPreload(modelContext: modelContext)
            }
            await self?.performSync(modelContext: modelContext, force: true)
        }
    }

    @MainActor
    private func performSync(modelContext: ModelContext, force: Bool) async {
        let baseCount = LibriVoxCatalogSync.syncedBookCount
        syncState = .syncing(fetched: baseCount)
        do {
            if force {
                try await LibriVoxCatalogSync.forceFullSync(modelContext: modelContext) { [weak self] fetched in
                    self?.syncState = .syncing(fetched: baseCount + fetched)
                }
            } else {
                try await LibriVoxCatalogSync.syncIfNeeded(modelContext: modelContext) { [weak self] fetched in
                    self?.syncState = .syncing(fetched: baseCount + fetched)
                }
            }
            syncState = .done
            await loadAvailableFilters(modelContext: modelContext)
            await loadFeaturedBooks(modelContext: modelContext)
        } catch {
            let offline = isNetworkUnavailable(error)
            let message = offline
                ? "No internet connection"
                : error.localizedDescription
            syncState = .failed(message, isOffline: offline)
        }
        syncTask = nil
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
