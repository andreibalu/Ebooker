//
//  SchemaCompatibilityTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Guardrail: catches accidental reintroduction of `@Attribute(.unique)` on synced models or
/// missing relationship inverses. Builds the same multi-configuration container shape used by
/// `AppDelegate` — once in-memory (smoke test) and once file-backed with the real CloudKit
/// `.private(...)` database (validates the synced schema actually satisfies CloudKit constraints
/// the way it will when the app launches with iCloud sync enabled).
struct SchemaCompatibilityTests {
    @Test func canBuildSyncedAndLocalConfigurationsInMemory() throws {
        let syncedSchema = Schema([
            Audiobook.self,
            AudioTrack.self,
            Moment.self,
            ReadingSession.self,
        ])
        let localSchema = Schema([LibriVoxBook.self])

        let syncedConfig = ModelConfiguration(
            "synced-test",
            schema: syncedSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let localConfig = ModelConfiguration(
            "local-test",
            schema: localSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(
            for: Audiobook.self,
            AudioTrack.self,
            Moment.self,
            ReadingSession.self,
            LibriVoxBook.self,
            configurations: syncedConfig, localConfig
        )

        // Sanity check: insert one of each model and read back.
        let context = ModelContext(container)
        let book = Audiobook(title: "Schema check", folderName: "schema-\(UUID().uuidString)")
        let track = AudioTrack(title: "Ch 1", originalFileName: "a.m4a", storedFileName: "001-a.m4a", orderIndex: 0, duration: 1, audiobook: book)
        book.tracks.append(track)
        let moment = Moment(trackIndex: 0, time: 0, label: "m", audiobook: book)
        book.moments.append(moment)
        let session = ReadingSession(
            date: .now,
            dayKey: "2026-05-21",
            hour: 12,
            minutes: 5,
            bookID: book.id,
            bookTitle: book.title,
            bookAuthor: "",
            isFreeBook: false
        )
        context.insert(book)
        context.insert(track)
        context.insert(moment)
        context.insert(session)
        try context.save()

        let audiobooks = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(audiobooks.count == 1)
        #expect(audiobooks.first?.tracks.count == 1)
        #expect(audiobooks.first?.moments.count == 1)
    }

    /// File-backed container with the production `.private(...)` CloudKit database. CloudKit
    /// validates the schema at store-load time — a missing default on a non-optional attribute
    /// or a missing relationship inverse on a synced model would fail this test, which is the
    /// regression we want to catch before it crashes a launch with sync enabled.
    @Test func syncedSchemaSatisfiesCloudKitConstraints() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-cloudkit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let syncedSchema = Schema([
            Audiobook.self,
            AudioTrack.self,
            Moment.self,
            ReadingSession.self,
        ])
        let syncedStoreURL = tempDir.appendingPathComponent("synced.store")
        let syncedConfig = ModelConfiguration(
            "synced-cloudkit-test",
            schema: syncedSchema,
            url: syncedStoreURL,
            cloudKitDatabase: .private(IcloudSyncGate.containerIdentifier)
        )

        // Building the container is the assertion — CloudKit shape validation happens at load.
        _ = try ModelContainer(
            for: Audiobook.self,
            AudioTrack.self,
            Moment.self,
            ReadingSession.self,
            configurations: syncedConfig
        )
    }

    @Test func contentFingerprintRoundTripsThroughModel() throws {
        let track = AudioTrack(
            title: "T",
            originalFileName: "a.m4a",
            storedFileName: "001-a.m4a",
            orderIndex: 0,
            duration: 1
        )
        #expect(track.contentFingerprint == nil)
        track.contentFingerprint = "deadbeef"
        #expect(track.contentFingerprint == "deadbeef")
    }
}
