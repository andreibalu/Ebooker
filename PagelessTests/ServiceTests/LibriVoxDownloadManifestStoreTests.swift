//
//  LibriVoxDownloadManifestStoreTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxDownloadManifestStoreTests {
    @Test func roundTripsManifest() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let job = makeJob(completed: [0])

        try harness.store.save(job)

        #expect(try harness.store.loadAll() == [job])
    }

    @Test func replacingManifestKeepsLatestState() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        var job = makeJob()
        try harness.store.save(job)
        job.completedIndexes = [0, 1]
        job.phase = .failed
        job.lastError = "Offline"

        try harness.store.save(job)

        #expect(try harness.store.loadAll() == [job])
        #expect(try harness.store.manifestFiles().count == 1)
    }

    @Test func taskIdentityRoundTripsAndRejectsMalformedDescriptions() {
        let attemptID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let identity = LibriVoxDownloadTaskIdentity(
            catalogID: "book",
            attemptID: attemptID,
            trackIndex: 3
        )

        #expect(LibriVoxDownloadTaskIdentity(description: identity.description) == identity)
        #expect(LibriVoxDownloadTaskIdentity(description: "book|bad") == nil)
        #expect(LibriVoxDownloadTaskIdentity(description: "book|not-a-uuid|3") == nil)
        #expect(LibriVoxDownloadTaskIdentity(description: "book|\(attemptID)|-1") == nil)
        #expect(LibriVoxDownloadTaskIdentity(description: "|\(attemptID)|1") == nil)
    }

    @Test func corruptManifestIsQuarantinedWhileValidManifestContinuesLoading() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let job = makeJob()
        try harness.store.save(job)
        try Data("{".utf8).write(to: harness.store.manifestsURL.appendingPathComponent("broken.json"))

        #expect(try harness.store.loadAll() == [job])
        #expect(try harness.store.quarantinedFiles().count == 1)
        #expect(try harness.store.manifestFiles().count == 1)
    }

    @Test func invalidPathManifestIsQuarantined() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let job = makeJob(stagingFolderName: "../escape")
        try FileManager.default.createDirectory(
            at: harness.store.manifestsURL,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(job).write(
            to: harness.store.manifestsURL.appendingPathComponent("invalid.json")
        )

        #expect(try harness.store.loadAll().isEmpty)
        #expect(try harness.store.quarantinedFiles().count == 1)
    }

    @Test func invalidURLDurationAndTrackOrderAreQuarantined() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        var job = makeJob()
        job.tracks = [
            job.tracks[0],
            .init(
                title: "Chapter 2",
                remoteURL: URL(string: "file:///tmp/2.mp3")!,
                durationSeconds: 0,
                storedFileName: "0002.mp3",
                orderIndex: 2
            )
        ]
        try FileManager.default.createDirectory(
            at: harness.store.manifestsURL,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(job).write(
            to: harness.store.manifestsURL.appendingPathComponent("\(job.attemptID.uuidString).json")
        )

        #expect(try harness.store.loadAll().isEmpty)
        #expect(try harness.store.quarantinedFiles().count == 1)
    }

    @Test func oldManifestMissingOrderIndexesMigratesByTrackPosition() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let job = makeJob()
        let encoded = try JSONEncoder().encode(job)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var tracks = try #require(object["tracks"] as? [[String: Any]])
        tracks = tracks.map { track in
            var migrated = track
            migrated.removeValue(forKey: "orderIndex")
            return migrated
        }
        object["tracks"] = tracks
        let oldData = try JSONSerialization.data(withJSONObject: object)
        try FileManager.default.createDirectory(
            at: harness.store.manifestsURL,
            withIntermediateDirectories: true
        )
        try oldData.write(
            to: harness.store.manifestsURL.appendingPathComponent("\(job.attemptID.uuidString).json")
        )

        #expect(try harness.store.loadAll() == [job])
    }

    @Test func deleteRemovesOnlyMatchingAttempt() throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let first = makeJob(catalogID: "a")
        let second = makeJob(catalogID: "b")
        try harness.store.save(first)
        try harness.store.save(second)

        try harness.store.delete(attemptID: first.attemptID)

        #expect(try harness.store.loadAll() == [second])
    }

    private func makeJob(
        catalogID: String = "book",
        completed: Set<Int> = [],
        stagingFolderName: String = "stage"
    ) -> LibriVoxDownloadJob {
        .init(
            catalogID: catalogID,
            attemptID: UUID(uuidString: catalogID == "book"
                ? "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
                : catalogID == "a"
                    ? "11111111-2222-3333-4444-555555555555"
                    : "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            title: "Jane Eyre",
            target: .fresh,
            stagingFolderName: stagingFolderName,
            tracks: [
                .init(
                    title: "Chapter 1",
                    remoteURL: URL(string: "https://example.com/1.mp3")!,
                    durationSeconds: 60,
                    storedFileName: "0001.mp3",
                    orderIndex: 0
                ),
                .init(
                    title: "Chapter 2",
                    remoteURL: URL(string: "https://example.com/2.mp3")!,
                    durationSeconds: 75,
                    storedFileName: "0002.mp3",
                    orderIndex: 1
                )
            ],
            completedIndexes: completed,
            phase: .downloading,
            lastError: nil
        )
    }
}

private struct StoreHarness {
    let rootURL: URL
    let store: LibriVoxDownloadManifestStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibriVoxManifestTests-\(UUID().uuidString)", isDirectory: true)
        store = LibriVoxDownloadManifestStore(rootURL: rootURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
