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
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runSearch(query: trimmed, modelContext: modelContext)
        }
    }

    @MainActor
    private func runSearch(query: String, modelContext: ModelContext) async {
        do {
            let predicate = #Predicate<LibriVoxBook> { book in
                book.title.localizedStandardContains(query) ||
                book.authorDisplay.localizedStandardContains(query) ||
                book.bookDescription.localizedStandardContains(query)
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = 150
            let raw = try modelContext.fetch(descriptor)
            let q = query.lowercased()
            searchResults = raw.sorted { rankScore($0, query: q) < rankScore($1, query: q) }
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
