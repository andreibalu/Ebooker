//
//  SchemaCompatibilityTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Validates synced model constraints by loading a file-backed container with the
/// production CloudKit database. Native E2E uses a local fixture store.
struct SchemaCompatibilityTests {

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
}
