//
//  BrowseLibriVoxViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

@Observable
final class BrowseLibriVoxViewModel {
    enum SyncState {
        case idle
        case syncing(fetched: Int)
        case done
        case failed(String)
    }

    var searchQuery: String = ""
    var searchResults: [LibriVoxBook] = []
    var syncState: SyncState = .idle

    private var searchTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    var lastSyncDescription: String {
        guard let date = LibriVoxCatalogSync.lastSyncDate else {
            return "Never synced"
        }
        return "Updated \(TimeFormatter.relativeDateString(for: date))"
    }

    var catalogCount: Int {
        LibriVoxCatalogSync.syncedBookCount
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
            searchResults = raw.sorted { a, b in
                rankScore(a, query: q) < rankScore(b, query: q)
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
            syncState = .failed(error.localizedDescription)
        }
        syncTask = nil
    }
}
