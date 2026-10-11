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
