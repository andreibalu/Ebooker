//
//  LibriVoxCollectionViewModel.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

@Observable
final class LibriVoxCollectionViewModel {
    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(isOffline: Bool)
    }

    var state: LoadState = .idle
    var books: [LibriVoxBook] = []

    /// Resolves the collection's books local-first from the `LibriVoxBook` cache, fetching
    /// only the IDs that aren't cached yet (fresh install before the full catalog sync).
    /// Fetched metadata is seeded through `LibriVoxCatalogSync.seed`, so a later full sync
    /// matches the rows by `id` instead of duplicating them. Offline with a partial cache
    /// degrades to showing whatever is cached.
    @MainActor
    func load(collection: LibriVoxCollection, modelContext: ModelContext) async {
        if case .loading = state { return }
        state = .loading

        let ids = collection.bookIDs
        var cached = fetchLocal(ids: ids, modelContext: modelContext)
        if cached.count < ids.count {
            let missing = ids.filter { id in !cached.contains { $0.id == id } }
            if let fetched = try? await LibriVoxAPIClient.fetchBooks(ids: missing), !fetched.isEmpty {
                try? LibriVoxCatalogSync.seed(fetched, into: modelContext)
                cached = fetchLocal(ids: ids, modelContext: modelContext)
            }
        }

        books = ordered(cached, by: ids)
        if books.isEmpty {
            state = .failed(isOffline: !NetworkMonitor.shared.isConnected)
        } else {
            state = .loaded
        }
    }

    @MainActor
    func retry(collection: LibriVoxCollection, modelContext: ModelContext) async {
        state = .idle
        await load(collection: collection, modelContext: modelContext)
    }

    // MARK: - Private

    private func fetchLocal(ids: [String], modelContext: ModelContext) -> [LibriVoxBook] {
        // Capture the array (not a Set) — `Array.contains` is the form SwiftData predicates support.
        let predicate = #Predicate<LibriVoxBook> { ids.contains($0.id) }
        return (try? modelContext.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }

    /// Preserves the curated order of the collection's ID list.
    private func ordered(_ books: [LibriVoxBook], by ids: [String]) -> [LibriVoxBook] {
        let byID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
}
