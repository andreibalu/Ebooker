//
//  LibraryImportFingerprintTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct LibraryImportFingerprintTests {
    @Test func fingerprintIsDeterministicForSameBytes() async throws {
        let url = try makeTempFile(named: "a.bin", bytes: bytes(count: 4096, pattern: 0xAB))
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await LibraryImportService.fingerprint(url: url, durationSeconds: 12.5)
        let second = await LibraryImportService.fingerprint(url: url, durationSeconds: 12.5)
        #expect(first != nil)
        #expect(first == second)
    }

    @Test func fingerprintDiffersAcrossDifferentBytes() async throws {
        let a = try makeTempFile(named: "a.bin", bytes: bytes(count: 4096, pattern: 0xAB))
        let b = try makeTempFile(named: "b.bin", bytes: bytes(count: 4096, pattern: 0xCD))
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }

        let fpA = await LibraryImportService.fingerprint(url: a, durationSeconds: 10)
        let fpB = await LibraryImportService.fingerprint(url: b, durationSeconds: 10)
        #expect(fpA != nil)
        #expect(fpB != nil)
        #expect(fpA != fpB)
    }

    @Test func fingerprintHandlesSmallFiles() async throws {
        // Smaller than 2MB cutoff → whole-file hash branch.
        let url = try makeTempFile(named: "small.bin", bytes: bytes(count: 1024, pattern: 0x42))
        defer { try? FileManager.default.removeItem(at: url) }

        let fp = await LibraryImportService.fingerprint(url: url, durationSeconds: 1)
        #expect(fp != nil)
        #expect(fp?.count == 64)
    }

    @Test func fingerprintIsRobustToFilenameChange() async throws {
        let payload = bytes(count: 8 * 1024, pattern: 0x77)
        let urlA = try makeTempFile(named: "first-name.bin", bytes: payload)
        let urlB = try makeTempFile(named: "second-name.bin", bytes: payload)
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let fpA = await LibraryImportService.fingerprint(url: urlA, durationSeconds: 4)
        let fpB = await LibraryImportService.fingerprint(url: urlB, durationSeconds: 4)
        #expect(fpA == fpB)
    }

    @Test func fingerprintReturnsNilForMissingFile() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("definitely-does-not-exist-\(UUID()).bin")
        let fp = await LibraryImportService.fingerprint(url: missing, durationSeconds: 1)
        #expect(fp == nil)
    }

    @Test func exactFingerprintMultisetMatchesWhenReordered() {
        let pending = makePending(fingerprints: ["chapter-a", "chapter-b"])
        let book = makeBook(fingerprints: ["chapter-b", "chapter-a"])

        #expect(LibraryImportService.hasExactFingerprintMultiset(pending, matching: book))
    }

    @Test func exactFingerprintMultisetPreservesRepeatedCounts() {
        let pending = makePending(fingerprints: ["repeated", "repeated", "other"])
        let sameCounts = makeBook(fingerprints: ["other", "repeated", "repeated"])
        let differentCounts = makeBook(fingerprints: ["other", "other", "repeated"])

        #expect(LibraryImportService.hasExactFingerprintMultiset(pending, matching: sameCounts))
        #expect(!LibraryImportService.hasExactFingerprintMultiset(pending, matching: differentCounts))
    }

    @Test func exactFingerprintMultisetRejectsPartialOverlap() {
        let pending = makePending(fingerprints: ["shared", "pending-only"])
        let book = makeBook(fingerprints: ["shared", "existing-only"])

        #expect(!LibraryImportService.hasExactFingerprintMultiset(pending, matching: book))
    }

    @Test func exactFingerprintMultisetRejectsNilPendingFingerprint() {
        let pending = makePending(fingerprints: ["chapter-a", nil])
        let book = makeBook(fingerprints: ["chapter-a", "chapter-b"])

        #expect(!LibraryImportService.hasExactFingerprintMultiset(pending, matching: book))
    }

    @Test func activeDuplicateLookupIgnoresFreeBooksAndOwnBookOrphans() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = makePending(fingerprints: ["same"])
        let freeBook = makeBook(fingerprints: ["same"], isFreeBook: true)
        let orphan = makeBook(fingerprints: ["same"], isDownloaded: false)
        context.insert(freeBook)
        context.insert(orphan)
        try context.save()

        #expect(try LibraryImportService.findActiveDuplicate(for: pending, modelContext: context) == nil)
    }

    @Test func activeDuplicateLookupFindsDownloadedOwnBook() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = makePending(fingerprints: ["chapter-b", "chapter-a"])
        let active = makeBook(fingerprints: ["chapter-a", "chapter-b"])
        context.insert(active)
        try context.save()

        #expect(try LibraryImportService.findActiveDuplicate(for: pending, modelContext: context) === active)
    }

    @Test func importRejectsDuplicateBeforeInsertionOrFileCopy() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = makePending(fingerprints: ["same"])
        let active = makeBook(fingerprints: ["same"])
        context.insert(active)
        try context.save()

        do {
            _ = try LibraryImportService.importAudiobook(
                from: pending,
                title: "Renamed Copy",
                author: "",
                modelContext: context
            )
            Issue.record("Expected duplicate import to throw")
        } catch LibraryImportError.alreadyInLibrary {
            // Expected: the missing source file was never copied.
        } catch {
            Issue.record("Expected alreadyInLibrary, got \(error)")
        }

        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }

    // MARK: - Helpers

    private func bytes(count: Int, pattern: UInt8) -> Data {
        Data(repeating: pattern, count: count)
    }

    private func makeTempFile(named name: String, bytes: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
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
                sourceURL: URL(fileURLWithPath: "/tmp/missing-import-\(index).m4a"),
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

    private func makeBook(
        fingerprints: [String?],
        isFreeBook: Bool = false,
        isDownloaded: Bool = true
    ) -> Audiobook {
        let book = Audiobook(
            title: "Existing Book",
            folderName: UUID().uuidString,
            isFreeBook: isFreeBook,
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
