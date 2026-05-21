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
/// `AppDelegate` against an in-memory store.
struct SchemaCompatibilityTests {
    @Test func canBuildSyncedAndLocalConfigurationsTogether() throws {
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
            isStoredInMemoryOnly: true
        )
        let localConfig = ModelConfiguration(
            "local-test",
            schema: localSchema,
            isStoredInMemoryOnly: true
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
