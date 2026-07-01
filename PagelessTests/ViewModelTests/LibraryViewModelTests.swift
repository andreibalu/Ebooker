//
//  LibraryViewModelTests.swift
//  PagelessTests
//

import Testing
import Foundation
import SwiftData
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

    @Test func duplicatePreparedImportAlertsAndCleansUpBeforeOrphanRouting() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vm = makeViewModel()
        let pending = makePending(fingerprints: ["same"])
        let active = makeBook(fingerprints: ["same"], isDownloaded: true)
        let orphan = makeBook(fingerprints: ["same"], isDownloaded: false)
        context.insert(active)
        context.insert(orphan)
        try context.save()
        vm.urlsHoldingSecurityAccess = pending.sourceURLs

        vm.routePreparedImport(pending, modelContext: context)

        #expect(vm.pendingImport == nil)
        #expect(vm.restoreMatch == nil)
        #expect(vm.urlsHoldingSecurityAccess.isEmpty)
        #expect(vm.alertTitle == "Already in Library")
        #expect(vm.isShowingAlert)
    }

    @Test func importRaceUsesDuplicateAlertAndCleanupPath() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vm = makeViewModel()
        let pending = makePending(fingerprints: ["same"])
        context.insert(makeBook(fingerprints: ["same"], isDownloaded: true))
        try context.save()
        vm.pendingImport = pending
        vm.urlsHoldingSecurityAccess = pending.sourceURLs

        try vm.importAudiobook(pending, title: "Copy", author: "", modelContext: context)

        #expect(vm.pendingImport == nil)
        #expect(vm.urlsHoldingSecurityAccess.isEmpty)
        #expect(vm.alertTitle == "Already in Library")
        #expect(vm.isShowingAlert)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
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

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makePending(fingerprints: [String?]) -> PendingImportSelection {
        let tracks = fingerprints.enumerated().map { index, fingerprint in
            TrackImportPreview(
                sourceURL: URL(fileURLWithPath: "/tmp/missing-vm-import-\(index).m4a"),
                title: "Chapter \(index + 1)",
                originalFileName: "chapter-\(index + 1).m4a",
                duration: 60,
                contentFingerprint: fingerprint
            )
        }
        return PendingImportSelection(
            sourceURLs: tracks.map(\.sourceURL),
            suggestedTitle: "Imported Book",
            suggestedAuthor: "",
            coverArtData: nil,
            tracks: tracks
        )
    }

    private func makeBook(fingerprints: [String?], isDownloaded: Bool) -> Audiobook {
        let book = Audiobook(
            title: "Existing Book",
            folderName: UUID().uuidString,
            isDownloaded: isDownloaded
        )
        for (index, fingerprint) in fingerprints.enumerated() {
            let track = AudioTrack(
                title: "Chapter \(index + 1)",
                originalFileName: "chapter-\(index + 1).m4a",
                storedFileName: "chapter-\(index + 1).m4a",
                orderIndex: index,
                duration: 60,
                audiobook: book
            )
            track.contentFingerprint = fingerprint
            book.tracks.append(track)
        }
        return book
    }
}
