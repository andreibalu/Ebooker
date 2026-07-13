//
//  OrphanRestoreServiceTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct OrphanRestoreServiceTests {
    @Test func findMatchPicksOrphanWithMatchingFingerprint() throws {
        let context = try makeInMemoryContext()

        let matching = makeOrphan(in: context, title: "Match Me", folderName: "match", fingerprints: ["abc", "def"])
        let other = makeOrphan(in: context, title: "Other", folderName: "other", fingerprints: ["xyz"])
        // Downloaded books must never be returned as orphans.
        let downloaded = Audiobook(title: "Downloaded", folderName: "dl", isDownloaded: true)
        let dlTrack = AudioTrack(title: "t", originalFileName: "t.m4a", storedFileName: "1-t.m4a", orderIndex: 0, duration: 1, audiobook: downloaded)
        dlTrack.contentFingerprint = "abc"
        downloaded.tracks.append(dlTrack)
        context.insert(downloaded)
        context.insert(dlTrack)
        try context.save()

        let pending = makePending(fingerprints: ["abc"])
        let found = OrphanRestoreService.findMatch(for: pending, modelContext: context)

        #expect(found?.title == matching.title)
        _ = other
    }

    @Test func findMatchReturnsNilWhenNoFingerprintMatches() throws {
        let context = try makeInMemoryContext()
        _ = makeOrphan(in: context, title: "A", folderName: "a", fingerprints: ["111"])
        _ = makeOrphan(in: context, title: "B", folderName: "b", fingerprints: ["222"])

        let pending = makePending(fingerprints: ["999"])
        let found = OrphanRestoreService.findMatch(for: pending, modelContext: context)
        #expect(found == nil)
    }

    @Test func findMatchReturnsNilWhenPendingHasNoFingerprints() throws {
        let context = try makeInMemoryContext()
        _ = makeOrphan(in: context, title: "A", folderName: "a", fingerprints: ["111"])
        let pending = makePending(fingerprints: [nil, nil])
        let found = OrphanRestoreService.findMatch(for: pending, modelContext: context)
        #expect(found == nil)
    }

    @Test func adoptCopiesFilesAndUpdatesTrackPointers() throws {
        let context = try makeInMemoryContext()
        let orphan = makeOrphan(in: context, title: "Original", folderName: "orphan-\(UUID().uuidString)", fingerprints: ["fp-1"])
        orphan.author = "An Author"

        // Add a moment so we can verify it's preserved after adoption.
        let moment = Moment(trackIndex: 0, time: 12.5, label: "Test moment", audiobook: orphan)
        context.insert(moment)
        orphan.moments.append(moment)
        try context.save()

        // Create a source file the user would be re-importing.
        let sourceURL = try makeTempAudio(named: "ch01.m4a", bytes: Data(repeating: 0xEE, count: 2048))
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }

        let pending = PendingImportSelection(
            sourceURLs: [sourceURL],
            suggestedTitle: "Adopted",
            suggestedAuthor: "",
            coverArtData: nil,
            tracks: [
                TrackImportPreview(
                    sourceURL: sourceURL,
                    title: "Chapter 1",
                    originalFileName: "ch01.m4a",
                    duration: 60,
                    contentFingerprint: "fp-1"
                )
            ]
        )

        let adopted = try OrphanRestoreService.adopt(orphan: orphan, pending: pending, modelContext: context)

        #expect(adopted === orphan)
        #expect(adopted.isDownloaded == true)
        #expect(adopted.tracks.count == 1)
        #expect(adopted.tracks.first?.contentFingerprint == "fp-1")
        #expect(adopted.tracks.first?.storedFileName.hasSuffix("ch01.m4a") == true)
        #expect(adopted.moments.count == 1)
        #expect(adopted.moments.first?.label == "Test moment")

        // The file should now exist in the orphan's folder.
        let folder = try storageFolder(for: orphan.folderName)
        let storedURL = folder.appendingPathComponent(adopted.tracks.first!.storedFileName)
        #expect(FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)))

        // Cleanup
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func mergeMovesLocalFilesIntoCloudEntryAndDeletesLocalRecord() throws {
        let (container, context) = try makeInMemoryContainerAndContext()

        // Cloud-only entry the user wants to keep (its moments/progress win).
        let cloudFolder = "cloud-\(UUID().uuidString)"
        let cloudEntry = makeOrphan(in: context, title: "Cloud Backup", folderName: cloudFolder, fingerprints: ["fp-1"])
        cloudEntry.progressTrackIndex = 0
        cloudEntry.progressTime = 99.0
        let cloudMoment = Moment(trackIndex: 0, time: 33.0, label: "Cloud moment", audiobook: cloudEntry)
        context.insert(cloudMoment)
        cloudEntry.moments.append(cloudMoment)
        try context.save()

        // Downloaded local book with a real file on disk that the user added as new.
        let localFolder = "local-\(UUID().uuidString)"
        let localBook = Audiobook(title: "Local Copy", folderName: localFolder, isDownloaded: true)
        context.insert(localBook)
        let localTrack = AudioTrack(
            title: "Chapter 1",
            originalFileName: "ch01.m4a",
            storedFileName: "001-ch01.m4a",
            orderIndex: 0,
            duration: 60,
            audiobook: localBook
        )
        localTrack.contentFingerprint = "fp-1"
        localBook.tracks.append(localTrack)
        context.insert(localTrack)
        try context.save()

        let localStorage = try storageFolder(for: localFolder)
        try FileManager.default.createDirectory(at: localStorage, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1024).write(to: localStorage.appendingPathComponent("001-ch01.m4a"))

        let localID = localBook.id
        var saveCalls = 0
        let environment = LibraryMutationEnvironment(
            rootURL: LibraryMutationTransaction.defaultAudiobooksRoot(),
            save: { context in
                saveCalls += 1
                if saveCalls == 2 { throw MergeMutationTestError.save }
                try context.save()
            }
        )
        let survivor = try OrphanRestoreService.merge(
            localBook: localBook,
            into: cloudEntry,
            modelContext: context,
            mutationEnvironment: environment
        )

        #expect(survivor === cloudEntry)
        #expect(saveCalls == 1)
        #expect(cloudEntry.isDownloaded == true)
        #expect(cloudEntry.progressTime == 99.0)
        #expect(cloudEntry.moments.first?.label == "Cloud moment")

        // The file now lives in the cloud entry's folder.
        let cloudStorage = try storageFolder(for: cloudFolder)
        let stored = cloudEntry.tracks.first!.storedFileName
        #expect(FileManager.default.fileExists(atPath: cloudStorage.appendingPathComponent(stored).path(percentEncoded: false)))

        // The duplicate local record is gone.
        let remaining = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(!remaining.contains { $0.id == localID })
        let refetched = ModelContext(container)
        let persisted = try refetched.fetch(FetchDescriptor<Audiobook>())
        #expect(persisted.contains { $0.id == cloudEntry.id && $0.isDownloaded })
        #expect(!persisted.contains { $0.id == localID })

        try? FileManager.default.removeItem(at: cloudStorage)
        try? FileManager.default.removeItem(at: localStorage)
    }

    @Test func mergeSaveFailureRestoresBothRecordsAndBothFoldersInFreshContext() throws {
        let (container, context) = try makeInMemoryContainerAndContext()
        let cloudFolder = "merge-cloud-failure-\(UUID().uuidString)"
        let cloudEntry = makeOrphan(in: context, title: "Cloud Backup", folderName: cloudFolder, fingerprints: ["fp-1"])

        let localFolder = "merge-local-failure-\(UUID().uuidString)"
        let localBook = Audiobook(title: "Local Copy", folderName: localFolder, isDownloaded: true)
        context.insert(localBook)
        let localTrack = AudioTrack(
            title: "Chapter 1",
            originalFileName: "ch01.m4a",
            storedFileName: "001-ch01.m4a",
            orderIndex: 0,
            duration: 60,
            audiobook: localBook
        )
        localTrack.contentFingerprint = "fp-1"
        localBook.tracks.append(localTrack)
        context.insert(localTrack)
        try context.save()

        let localStorage = try storageFolder(for: localFolder)
        try FileManager.default.createDirectory(at: localStorage, withIntermediateDirectories: true)
        try Data("local-audio".utf8).write(to: localStorage.appendingPathComponent("001-ch01.m4a"))
        let cloudStorage = try storageFolder(for: cloudFolder)
        let cloudID = cloudEntry.id
        let localID = localBook.id
        let root = LibraryMutationTransaction.defaultAudiobooksRoot()
        let environment = LibraryMutationEnvironment(rootURL: root, save: { _ in
            throw MergeMutationTestError.save
        })

        do {
            _ = try OrphanRestoreService.merge(
                localBook: localBook,
                into: cloudEntry,
                modelContext: context,
                mutationEnvironment: environment
            )
            Issue.record("Expected merge save failure")
        } catch MergeMutationTestError.save {
            // Expected.
        }

        let refetched = ModelContext(container)
        let books = try refetched.fetch(FetchDescriptor<Audiobook>())
        let restoredCloud = books.first { $0.id == cloudID }
        let restoredLocal = books.first { $0.id == localID }
        #expect(restoredCloud?.isDownloaded == false)
        #expect(restoredLocal?.isDownloaded == true)
        #expect(FileManager.default.fileExists(atPath: localStorage.appendingPathComponent("001-ch01.m4a").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: cloudStorage.path(percentEncoded: false)))

        try? FileManager.default.removeItem(at: localStorage)
        try? FileManager.default.removeItem(at: cloudStorage)
    }

    @Test func softDeleteRemovesFilesButPreservesRecord() throws {
        let context = try makeInMemoryContext()

        let folderName = "soft-\(UUID().uuidString)"
        let book = Audiobook(title: "Keep Me", folderName: folderName, isDownloaded: true)
        context.insert(book)
        let track = AudioTrack(
            title: "Chapter 1",
            originalFileName: "ch01.m4a",
            storedFileName: "001-ch01.m4a",
            orderIndex: 0,
            duration: 60,
            audiobook: book
        )
        track.contentFingerprint = "fp-keep"
        book.tracks.append(track)
        context.insert(track)
        let moment = Moment(trackIndex: 0, time: 5.0, label: "Saved moment", audiobook: book)
        context.insert(moment)
        book.moments.append(moment)
        try context.save()

        let storage = try storageFolder(for: folderName)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 512).write(to: storage.appendingPathComponent("001-ch01.m4a"))

        let bookID = book.id
        try LibraryImportService.softDeleteAudiobook(book, modelContext: context)

        #expect(book.isDownloaded == false)
        #expect(book.moments.first?.label == "Saved moment")
        #expect(book.tracks.first?.contentFingerprint == "fp-keep")
        #expect(!FileManager.default.fileExists(atPath: storage.path(percentEncoded: false)))

        // The record itself survives in the store (it's now a restorable orphan).
        let remaining = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(remaining.contains { $0.id == bookID })
    }

    // MARK: - Helpers

    private enum MergeMutationTestError: Error {
        case save
    }

    private func makeInMemoryContext() throws -> ModelContext {
        try makeInMemoryContainerAndContext().1
    }

    private func makeInMemoryContainerAndContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, ModelContext(container))
    }

    private func makeOrphan(
        in context: ModelContext,
        title: String,
        folderName: String,
        fingerprints: [String]
    ) -> Audiobook {
        let book = Audiobook(title: title, folderName: folderName, isDownloaded: false)
        context.insert(book)
        for (i, fp) in fingerprints.enumerated() {
            let track = AudioTrack(
                title: "Ch \(i+1)",
                originalFileName: "ch\(i+1).m4a",
                storedFileName: "00\(i+1)-ch\(i+1).m4a",
                orderIndex: i,
                duration: 60,
                audiobook: book
            )
            track.contentFingerprint = fp
            book.tracks.append(track)
            context.insert(track)
        }
        try? context.save()
        return book
    }

    private func makePending(fingerprints: [String?]) -> PendingImportSelection {
        let tracks: [TrackImportPreview] = fingerprints.enumerated().map { idx, fp in
            TrackImportPreview(
                sourceURL: URL(fileURLWithPath: "/tmp/file\(idx).m4a"),
                title: "Ch\(idx+1)",
                originalFileName: "ch\(idx+1).m4a",
                duration: 60,
                contentFingerprint: fp
            )
        }
        return PendingImportSelection(
            sourceURLs: tracks.map(\.sourceURL),
            suggestedTitle: "Title",
            suggestedAuthor: "",
            coverArtData: nil,
            tracks: tracks
        )
    }

    private func makeTempAudio(named: String, bytes: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orphan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(named)
        try bytes.write(to: url)
        return url
    }

    private func storageFolder(for folderName: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Audiobooks", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }
}
