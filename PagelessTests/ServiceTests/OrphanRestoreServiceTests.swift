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

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
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
