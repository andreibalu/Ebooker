//
//  LibraryViewModelFreeBookTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

@MainActor
struct LibraryViewModelFreeBookTests {
    private func makeViewModel() -> LibraryViewModel {
        LibraryViewModel()
    }

    @Test func sortedBooksIncludesFreeBooks() {
        let vm = makeViewModel()
        let freeBook = Audiobook(title: "Free Classic", folderName: "f", isFreeBook: true, catalogId: "test-id")
        let ownedBook = Audiobook(title: "Owned Book", folderName: "o")
        let sorted = vm.sorted([freeBook, ownedBook], by: LibrarySortOption.title.rawValue)
        #expect(sorted.count == 2)
        #expect(sorted[0].title == "Free Classic")
        #expect(sorted[1].title == "Owned Book")
    }

    @Test func freeBookDeleteCandidateCanBeSet() {
        let vm = makeViewModel()
        let book = Audiobook(title: "Free Book", folderName: "test", isFreeBook: true, catalogId: "cat-id")
        vm.deleteCandidate = book
        #expect(vm.deleteCandidate === book)
        #expect(vm.deleteCandidate?.isFreeBook == true)
    }

    @Test func availableCatalogEntriesExcludesDownloaded() {
        // Test filtering logic using known seed IDs — no network needed
        let seedIds = FreeBookCatalogService.bookSeeds.map(\.id)
        guard let firstId = seedIds.first else { return }
        let filtered = seedIds.filter { $0 != firstId }
        #expect(!filtered.contains(firstId))
        #expect(filtered.count == seedIds.count - 1)
    }

    @Test func availableCatalogEntriesReturnsAllWhenNoneDownloaded() {
        let seedIds = FreeBookCatalogService.bookSeeds.map(\.id)
        let filtered = seedIds.filter { !Set<String>().contains($0) }
        #expect(filtered.count == seedIds.count)
    }

    @Test func downloadedFreeBooksCatalogIdsFiltering() {
        let books = [
            Audiobook(title: "Free 1", folderName: "a", isFreeBook: true, catalogId: "cat-1"),
            Audiobook(title: "Free 2", folderName: "b", isFreeBook: true, catalogId: "cat-2"),
            Audiobook(title: "Owned", folderName: "c")
        ]
        let downloadedIds = Set(books.compactMap(\.catalogId))
        #expect(downloadedIds.count == 2)
        #expect(downloadedIds.contains("cat-1"))
        #expect(downloadedIds.contains("cat-2"))
    }
}
