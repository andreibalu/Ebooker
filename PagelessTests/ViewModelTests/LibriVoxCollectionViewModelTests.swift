//
//  LibriVoxCollectionViewModelTests.swift
//  PagelessTests
//

import Testing
import SwiftData
@testable import Pageless

@MainActor
struct LibriVoxCollectionViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LibriVoxBook.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    private func insertBook(id: String, title: String, into context: ModelContext) {
        context.insert(LibriVoxBook(
            id: id,
            title: title,
            authorDisplay: "Test Author",
            bookDescription: "A test book",
            language: "English",
            totalTimeSecs: 3600
        ))
    }

    @Test func loadResolvesFullyCachedCollectionWithoutNetwork() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let collection = LibriVoxCollection(
            id: "test", title: "Test", subtitle: "Sub", iconSystemName: "book",
            bookIDs: ["10", "20", "30"]
        )
        insertBook(id: "30", title: "Third", into: context)
        insertBook(id: "10", title: "First", into: context)
        insertBook(id: "20", title: "Second", into: context)
        try context.save()

        let vm = LibriVoxCollectionViewModel()
        await vm.load(collection: collection, modelContext: context)

        guard case .loaded = vm.state else {
            Issue.record("Expected loaded state, got \(vm.state)")
            return
        }
        #expect(vm.books.map(\.id) == ["10", "20", "30"], "Curated order must be preserved")
    }

    @Test func loadDegradesToPartialCacheWhenSomeIDsUnavailable() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // "999999999" never resolves (network fetch returns nothing for it); the cached
        // book must still be shown rather than failing the whole collection.
        let collection = LibriVoxCollection(
            id: "test", title: "Test", subtitle: "Sub", iconSystemName: "book",
            bookIDs: ["10", "999999999"]
        )
        insertBook(id: "10", title: "First", into: context)
        try context.save()

        let vm = LibriVoxCollectionViewModel()
        await vm.load(collection: collection, modelContext: context)

        guard case .loaded = vm.state else {
            Issue.record("Expected loaded state, got \(vm.state)")
            return
        }
        #expect(vm.books.map(\.id) == ["10"])
    }
}
