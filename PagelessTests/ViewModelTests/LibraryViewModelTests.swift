//
//  LibraryViewModelTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

@MainActor
struct LibraryViewModelTests {
    private func makeViewModel() -> LibraryViewModel {
        LibraryViewModel()
    }

    private func makeBooks() -> [Audiobook] {
        let a = Audiobook(title: "Zebra Book", author: "Zach", folderName: "z", totalDuration: 100, currentTime: 0)
        let b = Audiobook(title: "Alpha Book", author: "Adam", folderName: "a", totalDuration: 300, currentTime: 0)
        let c = Audiobook(title: "Middle Book", author: "Mike", folderName: "m", totalDuration: 200, currentTime: 0)
        return [a, b, c]
    }

    @Test func sortByTitle() {
        let vm = makeViewModel()
        let books = makeBooks()
        let sorted = vm.sorted(books, by: LibrarySortOption.title.rawValue)

        #expect(sorted[0].title == "Alpha Book")
        #expect(sorted[1].title == "Middle Book")
        #expect(sorted[2].title == "Zebra Book")
    }

    @Test func sortByAuthor() {
        let vm = makeViewModel()
        let books = makeBooks()
        let sorted = vm.sorted(books, by: LibrarySortOption.author.rawValue)

        #expect(sorted[0].author == "Adam")
        #expect(sorted[1].author == "Mike")
        #expect(sorted[2].author == "Zach")
    }

    @Test func sortByDuration() {
        let vm = makeViewModel()
        let books = makeBooks()
        let sorted = vm.sorted(books, by: LibrarySortOption.duration.rawValue)

        #expect(sorted[0].totalDuration == 300)
        #expect(sorted[1].totalDuration == 200)
        #expect(sorted[2].totalDuration == 100)
    }

    @Test func initialStateIsClean() {
        let vm = makeViewModel()

        #expect(vm.pendingImport == nil)
        #expect(vm.urlsHoldingSecurityAccess.isEmpty)
        #expect(vm.deleteCandidate == nil)
        #expect(vm.renameCandidate == nil)
        #expect(vm.renameTitleInput == "")
        #expect(vm.alertMessage == "")
        #expect(vm.isShowingAlert == false)
    }

    @Test func presentAlertSetsState() {
        let vm = makeViewModel()

        vm.presentAlert(message: "Test error")

        #expect(vm.alertMessage == "Test error")
        #expect(vm.isShowingAlert == true)
    }

    @Test func beginRenameSetsState() {
        let vm = makeViewModel()
        let book = Audiobook(title: "Original Title", folderName: "test")

        vm.beginRename(book)

        #expect(vm.renameCandidate === book)
        #expect(vm.renameTitleInput == "Original Title")
    }

    @Test func commitRenameUpdatesTitle() {
        let vm = makeViewModel()
        let book = Audiobook(title: "Old Title", folderName: "test")

        vm.beginRename(book)
        vm.renameTitleInput = "New Title"
        vm.commitRename()

        #expect(book.title == "New Title")
        #expect(vm.renameCandidate == nil)
    }

    @Test func commitRenameIgnoresEmptyInput() {
        let vm = makeViewModel()
        let book = Audiobook(title: "Keep This", folderName: "test")

        vm.beginRename(book)
        vm.renameTitleInput = "   "
        vm.commitRename()

        #expect(book.title == "Keep This")
    }
}
