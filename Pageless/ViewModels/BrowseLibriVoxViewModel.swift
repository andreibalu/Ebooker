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

    private var searchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    // MARK: - Download tracking

    func registerDownload(book: LibriVoxBook, total: Int) {
        activeDownloads[book.id] = ActiveLibriVoxDownload(id: book.id, book: book, completed: 0, total: total)
    }

    func updateDownloadProgress(bookId: String, completed: Int, total: Int) {
        activeDownloads[bookId]?.completed = completed
        activeDownloads[bookId]?.total = total
    }

    func completeDownload(bookId: String) {
        activeDownloads.removeValue(forKey: bookId)
    }

    func cancelOrFailDownload(bookId: String) {
        activeDownloads.removeValue(forKey: bookId)
    }

    var lastSyncDescription: String {
        guard let date = LibriVoxCatalogSync.lastSyncDate else { return "Never synced" }
        return "Updated \(TimeFormatter.relativeDateString(for: date))"
    }

    var catalogCount: Int { LibriVoxCatalogSync.syncedBookCount }

    /// True while the very first catalog download is running (no data cached yet).
    var isFirstTimeLoading: Bool {
        if case .syncing = syncState { return LibriVoxCatalogSync.syncedBookCount == 0 }
        return false
    }

    /// Network is unreachable and there is no cached catalog to search.
    var isOfflineWithNoData: Bool {
        if case .failed(_, let offline) = syncState {
            return offline && LibriVoxCatalogSync.syncedBookCount == 0
        }
        return false
    }

    /// Network is unreachable but there is a cached catalog the user can still search.
    var isOfflineWithCachedData: Bool {
        if case .failed(_, let offline) = syncState {
            return offline && LibriVoxCatalogSync.syncedBookCount > 0
        }
        return false
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

    // MARK: - Sync

    func triggerSyncIfNeeded(modelContext: ModelContext) {
        guard syncTask == nil else { return }
        guard case .idle = syncState else { return }
        syncTask = Task { [weak self] in
            await self?.performSync(modelContext: modelContext, force: false)
        }
    }

    func forceRefresh(modelContext: ModelContext) {
        syncTask?.cancel()
        availableLanguages = []
        availableGenres = []
        syncTask = Task { [weak self] in
            await self?.performSync(modelContext: modelContext, force: true)
        }
    }

    @MainActor
    private func performSync(modelContext: ModelContext, force: Bool) async {
        syncState = .syncing(fetched: 0)
        do {
            if force {
                try await LibriVoxCatalogSync.forceFullSync(modelContext: modelContext) { [weak self] fetched in
                    self?.syncState = .syncing(fetched: fetched)
                }
            } else {
                try await LibriVoxCatalogSync.syncIfNeeded(modelContext: modelContext) { [weak self] fetched in
                    self?.syncState = .syncing(fetched: fetched)
                }
            }
            syncState = .done
            await loadAvailableFilters(modelContext: modelContext)
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
