//
//  FreeBookDownloadServiceTests.swift
//  PagelessTests
//

import Testing
import CryptoKit
import Foundation
import SwiftData
@testable import Pageless

@MainActor
struct FreeBookDownloadServiceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeSampleCatalogEntry(id: String = "test-book") -> FreeBookCatalogEntry {
        FreeBookCatalogEntry(
            id: id,
            title: "Test Book",
            author: "Test Author",
            description: "A test book.",
            coverAssetName: nil,
            totalDurationSeconds: 3600,
            downloadSizeMB: 25.0,
            tracks: [
                FreeBookTrackEntry(
                    id: "test-ch01",
                    title: "Chapter 1",
                    fileName: "chapter_01.mp3",
                    downloadURL: "https://example.com/ch01.mp3",
                    durationSeconds: 1800,
                    orderIndex: 0
                ),
                FreeBookTrackEntry(
                    id: "test-ch02",
                    title: "Chapter 2",
                    fileName: "chapter_02.mp3",
                    downloadURL: "https://example.com/ch02.mp3",
                    durationSeconds: 1800,
                    orderIndex: 1
                )
            ]
        )
    }

    // MARK: - State Tests

    @Test func initialStateHasNoActiveDownloads() {
        let service = FreeBookDownloadService()
        #expect(service.activeDownloads.isEmpty)
    }

    @Test func initialStateHasNoProgress() {
        let service = FreeBookDownloadService()
        #expect(service.downloadProgress.isEmpty)
    }

    @Test func initialStateHasNoErrors() {
        let service = FreeBookDownloadService()
        #expect(service.downloadErrors.isEmpty)
    }

    @Test func processDeathManifestRoundTripPreservesFullCatalogAndAttemptIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LegacyFreeBookDownloadManifestStore(rootURL: root)
        let entry = makeSampleCatalogEntry()
        let attemptID = UUID()
        let job = LegacyFreeBookDownloadJob(
            attemptID: attemptID,
            catalogEntry: entry,
            folderName: "legacy-folder",
            completedIndexes: [0],
            phase: .downloading,
            lastError: nil
        )

        try store.save(job)

        #expect(try store.loadAll() == [job])
    }

    @Test func fileMetadataMatchesKnownSHA256AndByteCount() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metadata-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)

        let metadata = try LibriVoxDownloadService.fileMetadata(at: url)

        #expect(metadata.byteCount == 5)
        #expect(metadata.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func fileMetadataHashesDataAcrossMultipleReadChunks() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunked-metadata-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        let chunk = Data(repeating: 0xA5, count: 1_048_576)
        let tail = Data(repeating: 0x5A, count: 17)
        try Data().write(to: url)
        let file = try FileHandle(forWritingTo: url)
        try file.write(contentsOf: chunk)
        try file.write(contentsOf: chunk)
        try file.write(contentsOf: tail)
        try file.close()

        var expectedHasher = SHA256()
        expectedHasher.update(data: chunk)
        expectedHasher.update(data: chunk)
        expectedHasher.update(data: tail)
        let expectedHash = expectedHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        let metadata = try LibriVoxDownloadService.fileMetadata(at: url)

        #expect(metadata.byteCount == 2_097_169)
        #expect(metadata.sha256 == expectedHash)
    }

    @Test func relaunchReconciliationReschedulesMissingAndCleansCommittedJob() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-reconcile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LegacyFreeBookDownloadManifestStore(rootURL: root)
        let context = try makeContext()
        let missingEntry = makeSampleCatalogEntry(id: "missing-book")
        let missingJob = LegacyFreeBookDownloadJob(
            attemptID: UUID(),
            catalogEntry: missingEntry,
            folderName: "relaunch-folder",
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
        try store.save(missingJob)

        let committedEntry = makeSampleCatalogEntry(id: "committed-book")
        let folderName = "legacy-committed-folder-\(UUID().uuidString)"
        let folder = try FreeBookDownloadService.storageFolderURL(for: folderName)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storedNames = committedEntry.tracks.map {
            String(format: "%03d", $0.orderIndex + 1) + "-" + $0.fileName
        }
        for name in storedNames {
            try Data("live-\(name)".utf8).write(to: folder.appendingPathComponent(name))
        }
        let audiobook = Audiobook(
            title: committedEntry.title,
            author: committedEntry.author,
            folderName: folderName,
            isFreeBook: true,
            catalogId: committedEntry.id,
            isDownloaded: true
        )
        for (index, track) in committedEntry.tracks.enumerated() {
            let saved = AudioTrack(
                title: track.title,
                originalFileName: track.fileName,
                storedFileName: storedNames[index],
                orderIndex: index,
                duration: track.durationSeconds,
                audiobook: audiobook
            )
            audiobook.tracks.append(saved)
            context.insert(saved)
        }
        context.insert(audiobook)
        try context.save()
        let committedJob = LegacyFreeBookDownloadJob(
            attemptID: UUID(),
            catalogEntry: committedEntry,
            folderName: "stale-relaunch-folder",
            completedIndexes: Set(committedEntry.tracks.map(\.orderIndex)),
            phase: .downloading,
            lastError: nil
        )
        try store.save(committedJob)
        let service = FreeBookDownloadService(manifestStore: store)

        #expect(await service.restoreBackgroundSession(modelContext: context))
        #expect(try store.loadAll() == [missingJob])
        #expect(service.activeDownloads == [missingEntry.id])
        #expect(service.downloadProgress[missingEntry.id] == 0)
        for name in storedNames {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        }

        service.cancelDownload(catalogId: missingEntry.id)
        for _ in 0..<40 {
            if try store.loadAll().isEmpty { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(try store.loadAll().isEmpty)
        #expect(service.activeDownloads.isEmpty)
        #expect(service.downloadProgress[missingEntry.id] == nil)

        // A second reconciliation cancels any task that outlived the cancellation
        // callback, proving this test does not leave a real background task alive.
        #expect(await service.restoreBackgroundSession(modelContext: context))
        try await Task.sleep(for: .milliseconds(50))
        #expect(try store.loadAll().isEmpty)
    }

    @Test func newServiceResolvesStableTaskDescriptionAfterTaskIdentifierChanges() {
        let attemptID = UUID()
        let identity = LegacyFreeBookDownloadTaskIdentity(
            catalogID: "book",
            attemptID: attemptID,
            trackIndex: 3
        )

        let restored = LegacyFreeBookDownloadTaskIdentity(description: identity.description)
        #expect(restored == identity)
    }

    @Test func cancellationMatchesPersistedTaskByAttemptIdentityBeforeContextRestore() {
        let job = LegacyFreeBookDownloadJob(
            attemptID: UUID(),
            catalogEntry: makeSampleCatalogEntry(),
            folderName: "folder",
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
        let identity = LegacyFreeBookDownloadTaskIdentity(
            catalogID: job.catalogID,
            attemptID: job.attemptID,
            trackIndex: 1
        )

        #expect(FreeBookDownloadService.shouldCancelPersistedTask(
            taskDescription: identity.description,
            catalogID: job.catalogID,
            attemptIDs: [job.attemptID],
            jobs: [job]
        ))
        #expect(!FreeBookDownloadService.shouldCancelPersistedTask(
            taskDescription: LegacyFreeBookDownloadTaskIdentity(
                catalogID: job.catalogID,
                attemptID: UUID(),
                trackIndex: 1
            ).description,
            catalogID: job.catalogID,
            attemptIDs: [job.attemptID],
            jobs: [job]
        ))
    }

    @Test func malformedLegacyManifestIsQuarantinedWhileValidManifestContinuesLoading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LegacyFreeBookDownloadManifestStore(rootURL: root)
        let valid = LegacyFreeBookDownloadJob(
            attemptID: UUID(),
            catalogEntry: makeSampleCatalogEntry(),
            folderName: "legacy-folder",
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
        try store.save(valid)
        let manifests = root.appendingPathComponent("Manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: manifests.appendingPathComponent("bad.json")
        )

        #expect(try store.loadAll() == [valid])
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Corrupt", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        #expect(quarantined.count == 1)
    }

    @Test func invalidLegacyTrackShapeIsQuarantined() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LegacyFreeBookDownloadManifestStore(rootURL: root)
        let entry = FreeBookCatalogEntry(
            id: "invalid",
            title: "Invalid",
            author: "",
            description: "",
            coverAssetName: nil,
            totalDurationSeconds: 1,
            downloadSizeMB: 1,
            tracks: [FreeBookTrackEntry(
                id: "t",
                title: "Track",
                fileName: "track.mp3",
                downloadURL: "file:///tmp/track.mp3",
                durationSeconds: 0,
                orderIndex: 2
            )]
        )
        let job = LegacyFreeBookDownloadJob(
            attemptID: UUID(),
            catalogEntry: entry,
            folderName: "folder",
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
        let manifests = root.appendingPathComponent("Manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try JSONEncoder().encode(job).write(
            to: manifests.appendingPathComponent("\(job.attemptID.uuidString).json")
        )

        #expect(try store.loadAll().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Corrupt", isDirectory: true),
            includingPropertiesForKeys: nil
        ).count == 1)
    }

    @Test func staleLegacyCallbackCannotPassAttemptOrPhaseGate() {
        let attemptID = UUID()
        let activeAttemptID = UUID()
        let entry = makeSampleCatalogEntry()
        let context = FreeBookDownloadService.DownloadTaskContext(
            attemptID: attemptID,
            trackIndex: 0,
            catalogId: entry.id,
            trackEntry: entry.tracks[0],
            folderName: "folder"
        )
        let downloading = LegacyFreeBookDownloadJob(
            attemptID: attemptID,
            catalogEntry: entry,
            folderName: "folder",
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
        let failed = LegacyFreeBookDownloadJob(
            attemptID: attemptID,
            catalogEntry: entry,
            folderName: "folder",
            completedIndexes: [],
            phase: .failed,
            lastError: "old"
        )

        #expect(!FreeBookDownloadService.acceptsCallback(
            context: context,
            job: downloading,
            activeAttemptID: activeAttemptID
        ))
        #expect(!FreeBookDownloadService.acceptsCallback(
            context: context,
            job: failed,
            activeAttemptID: attemptID
        ))
        #expect(FreeBookDownloadService.acceptsCallback(
            context: context,
            job: downloading,
            activeAttemptID: attemptID
        ))
    }

    @Test func replayOfCommittedLegacyDownloadPreservesLiveFilesAndRemovesDuplicateFolder() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let liveFolderName = "legacy-live-\(UUID().uuidString)"
        let liveFolder = try FreeBookDownloadService.storageFolderURL(for: liveFolderName)
        defer { try? FileManager.default.removeItem(at: liveFolder) }
        let liveFileNames = entry.tracks.map {
            String(format: "%03d", $0.orderIndex + 1) + "-" + $0.fileName
        }
        for fileName in liveFileNames {
            try Data("live-\(fileName)".utf8).write(to: liveFolder.appendingPathComponent(fileName))
        }
        let audiobook = Audiobook(
            title: entry.title,
            author: entry.author,
            folderName: liveFolderName,
            isFreeBook: true,
            catalogId: entry.id,
            isDownloaded: true
        )
        for (index, track) in entry.tracks.enumerated() {
            let saved = AudioTrack(
                title: track.title,
                originalFileName: track.fileName,
                storedFileName: liveFileNames[index],
                orderIndex: index,
                duration: track.durationSeconds,
                audiobook: audiobook
            )
            audiobook.tracks.append(saved)
            context.insert(saved)
        }
        context.insert(audiobook)
        try context.save()

        let duplicateFolderName = "legacy-duplicate-\(UUID().uuidString)"
        let duplicateFolder = try FreeBookDownloadService.storageFolderURL(for: duplicateFolderName)
        try Data("duplicate".utf8).write(to: duplicateFolder.appendingPathComponent("junk.mp3"))
        defer { try? FileManager.default.removeItem(at: duplicateFolder) }

        let result = try FreeBookDownloadService().finalizeDownload(
            catalogEntry: entry,
            folderName: duplicateFolderName,
            coverData: nil,
            modelContext: context
        )

        #expect(result === audiobook)
        #expect(!FileManager.default.fileExists(atPath: duplicateFolder.path(percentEncoded: false)))
        for fileName in liveFileNames {
            #expect(try Data(contentsOf: liveFolder.appendingPathComponent(fileName)) == Data("live-\(fileName)".utf8))
        }
    }

    // MARK: - Mock Protocol Tests

    @Test func mockStartDownloadAddsToActiveDownloads() {
        let mock = MockFreeBookDownloadService()
        let entry = makeSampleCatalogEntry()
        mock.startDownload(entry: entry)
        #expect(mock.activeDownloads.contains("test-book"))
    }

    @Test func mockCancelDownloadRemovesFromActiveDownloads() {
        let mock = MockFreeBookDownloadService()
        let entry = makeSampleCatalogEntry()
        mock.startDownload(entry: entry)
        mock.cancelDownload(catalogId: "test-book")
        #expect(!mock.activeDownloads.contains("test-book"))
    }

    @Test func mockStartDownloadSetsInitialProgress() {
        let mock = MockFreeBookDownloadService()
        let entry = makeSampleCatalogEntry()
        mock.startDownload(entry: entry)
        #expect(mock.downloadProgress["test-book"] == 0.0)
    }

    // MARK: - Finalization Tests

    @Test func finalizationCreatesAudiobookWithCatalogId() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let folderName = "test-folder-uuid"

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: folderName, coverData: nil, modelContext: context)

        let audiobooks = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(audiobooks.count == 1)
        #expect(audiobooks.first?.catalogId == "test-book")
    }

    @Test func finalizationCreatesCorrectNumberOfTracks() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: "folder", coverData: nil, modelContext: context)

        let tracks = try context.fetch(FetchDescriptor<AudioTrack>())
        #expect(tracks.count == 2)
    }

    @Test func finalizationSetsIsFreeBookTrue() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: "folder", coverData: nil, modelContext: context)

        let audiobooks = try context.fetch(FetchDescriptor<Audiobook>())
        #expect(audiobooks.first?.isFreeBook == true)
    }

    @Test func finalizationUsesCorrectStoredFileNames() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()

        let service = FreeBookDownloadService()
        try service.finalizeDownload(catalogEntry: entry, folderName: "folder", coverData: nil, modelContext: context)

        let tracks = try context.fetch(FetchDescriptor<AudioTrack>())
        let sortedTracks = tracks.sorted { $0.orderIndex < $1.orderIndex }
        #expect(sortedTracks[0].storedFileName == "001-chapter_01.mp3")
        #expect(sortedTracks[1].storedFileName == "002-chapter_02.mp3")
    }

    // MARK: - Identity Guard Tests

    @Test func admissionRejectsActiveQueuedAndPersistedCatalogIds() throws {
        let container = try ModelContainer(
            for: Schema([Audiobook.self, AudioTrack.self, Moment.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        let persisted = Audiobook(
            title: "Persisted",
            folderName: "persisted",
            isFreeBook: true,
            catalogId: "persisted"
        )
        context.insert(persisted)
        try context.save()

        #expect(try !FreeBookDownloadService.shouldAcceptDownload(
            catalogId: "active",
            activeCatalogIds: ["active"],
            queuedCatalogIds: [],
            modelContext: context
        ))
        #expect(try !FreeBookDownloadService.shouldAcceptDownload(
            catalogId: "queued",
            activeCatalogIds: [],
            queuedCatalogIds: ["queued"],
            modelContext: context
        ))
        #expect(try !FreeBookDownloadService.shouldAcceptDownload(
            catalogId: "persisted",
            activeCatalogIds: [],
            queuedCatalogIds: [],
            modelContext: context
        ))
        #expect(try FreeBookDownloadService.shouldAcceptDownload(
            catalogId: "new",
            activeCatalogIds: [],
            queuedCatalogIds: [],
            modelContext: context
        ))
    }

    @Test(arguments: [false, true])
    func admissionAllowsStreamingAndArchivedIdentityPromotion(archived: Bool) throws {
        let context = try makeContext()
        let existing = Audiobook(
            title: "Existing",
            folderName: "existing",
            isFreeBook: true,
            catalogId: "promote",
            isDownloaded: false
        )
        existing.isArchived = archived
        context.insert(existing)
        try context.save()

        #expect(try FreeBookDownloadService.shouldAcceptDownload(
            catalogId: "promote",
            activeCatalogIds: [],
            queuedCatalogIds: [],
            modelContext: context
        ))
    }

    @Test func finalizationReusesPersistedCatalogIdentity() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let existing = Audiobook(
            title: "Existing",
            folderName: "existing-folder",
            isFreeBook: true,
            catalogId: entry.id
        )
        context.insert(existing)
        try context.save()

        let service = FreeBookDownloadService()
        let result = try service.finalizeDownload(
            catalogEntry: entry,
            folderName: "fresh-folder",
            coverData: nil,
            modelContext: context
        )

        #expect(result === existing)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AudioTrack>()).isEmpty)
    }

    @Test(arguments: [false, true])
    func finalizationPromotesStreamingAndArchivedCatalogIdentity(archived: Bool) throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let existing = Audiobook(
            title: "Existing",
            folderName: "old-folder",
            isFreeBook: true,
            catalogId: entry.id,
            isDownloaded: false
        )
        existing.isArchived = archived
        existing.currentTime = 91
        context.insert(existing)
        try context.save()

        let folderName = "legacy-fresh-\(UUID().uuidString)"
        let folderURL = try FreeBookDownloadService.storageFolderURL(for: folderName)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        try Data("audio".utf8).write(to: folderURL.appendingPathComponent("001-chapter_01.mp3"))

        let result = try FreeBookDownloadService().finalizeDownload(
            catalogEntry: entry,
            folderName: folderName,
            coverData: nil,
            modelContext: context
        )

        #expect(result === existing)
        #expect(result.isDownloaded)
        #expect(!result.isArchived)
        #expect(result.currentTime == 91)
        #expect(result.folderName == folderName)
        #expect(result.tracks.count == entry.tracks.count)
        #expect(FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)))
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }

    @Test func finalizationOfDownloadedIdentityRemovesRealFreshFolder() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let existing = Audiobook(
            title: "Existing",
            folderName: "existing-folder",
            isFreeBook: true,
            catalogId: entry.id
        )
        context.insert(existing)
        try context.save()

        let folderName = "legacy-duplicate-\(UUID().uuidString)"
        let folderURL = try FreeBookDownloadService.storageFolderURL(for: folderName)
        try Data("audio".utf8).write(to: folderURL.appendingPathComponent("partial.mp3"))

        let result = try FreeBookDownloadService().finalizeDownload(
            catalogEntry: entry,
            folderName: folderName,
            coverData: nil,
            modelContext: context
        )

        #expect(result === existing)
        #expect(!FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)))
    }

    @Test func freshFinalizationSaveFailureUnwindsOwnedModelsAndFolderOnly() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let unrelated = Audiobook(title: "Original", folderName: "unrelated")
        context.insert(unrelated)
        try context.save()
        unrelated.title = "Unsaved edit"
        let folderName = "legacy-fresh-save-failure-\(UUID().uuidString)"
        let folderURL = try FreeBookDownloadService.storageFolderURL(for: folderName)
        try Data("audio".utf8).write(to: folderURL.appendingPathComponent("001-chapter_01.mp3"))
        let service = FreeBookDownloadService()

        #expect(throws: LegacyInjectedSaveFailure.self) {
            try service.finalizeDownload(
                catalogEntry: entry,
                folderName: folderName,
                coverData: nil,
                modelContext: context,
                saveModelContext: { _ in throw LegacyInjectedSaveFailure() }
            )
        }

        #expect(try FreeBookIdentityService.match(catalogId: entry.id, modelContext: context) == nil)
        #expect(unrelated.title == "Unsaved edit")
        #expect(!FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)))

        let retryFolder = try FreeBookDownloadService.storageFolderURL(for: folderName)
        try Data("audio".utf8).write(to: retryFolder.appendingPathComponent("001-chapter_01.mp3"))
        let retried = try service.finalizeDownload(
            catalogEntry: entry,
            folderName: folderName,
            coverData: nil,
            modelContext: context
        )
        let refetched = try FreeBookIdentityService.match(catalogId: entry.id, modelContext: context)
        #expect(refetched?.audiobook.id == retried.id)
        #expect(refetched?.classification == .downloadedActive)
        #expect(FileManager.default.fileExists(atPath: retryFolder.path(percentEncoded: false)))
        #expect(unrelated.title == "Unsaved edit")
        try? FileManager.default.removeItem(at: retryFolder)
    }

    @Test func promotionFinalizationSaveFailureRestoresIdentityAndRemovesFolderOnly() throws {
        let context = try makeContext()
        let entry = makeSampleCatalogEntry()
        let existing = Audiobook(
            title: "Existing",
            folderName: "old-folder",
            isFreeBook: true,
            catalogId: entry.id,
            isDownloaded: false
        )
        existing.isArchived = true
        existing.currentTime = 91
        let unrelated = Audiobook(title: "Original", folderName: "unrelated")
        context.insert(existing)
        context.insert(unrelated)
        try context.save()
        unrelated.title = "Unsaved edit"
        let folderName = "legacy-promotion-save-failure-\(UUID().uuidString)"
        let folderURL = try FreeBookDownloadService.storageFolderURL(for: folderName)
        try Data("audio".utf8).write(to: folderURL.appendingPathComponent("001-chapter_01.mp3"))
        let service = FreeBookDownloadService()

        #expect(throws: LegacyInjectedSaveFailure.self) {
            try service.finalizeDownload(
                catalogEntry: entry,
                folderName: folderName,
                coverData: nil,
                modelContext: context,
                saveModelContext: { _ in throw LegacyInjectedSaveFailure() }
            )
        }

        #expect(existing.isArchived)
        #expect(!existing.isDownloaded)
        #expect(existing.folderName == "old-folder")
        #expect(existing.currentTime == 91)
        #expect(existing.tracks.isEmpty)
        #expect(unrelated.title == "Unsaved edit")
        #expect(!FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)))

        let retryFolder = try FreeBookDownloadService.storageFolderURL(for: folderName)
        try Data("audio".utf8).write(to: retryFolder.appendingPathComponent("001-chapter_01.mp3"))
        let retried = try service.finalizeDownload(
            catalogEntry: entry,
            folderName: folderName,
            coverData: nil,
            modelContext: context
        )
        let refetched = try FreeBookIdentityService.match(catalogId: entry.id, modelContext: context)
        #expect(refetched?.audiobook.id == retried.id)
        #expect(refetched?.classification == .downloadedActive)
        #expect(FileManager.default.fileExists(atPath: retryFolder.path(percentEncoded: false)))
        #expect(unrelated.title == "Unsaved edit")
        try? FileManager.default.removeItem(at: retryFolder)
    }

    @Test func queueHandoffSkipsIdentityThatBecamePersisted() throws {
        let context = try makeContext()
        let stale = makeSampleCatalogEntry()
        let fresh = FreeBookCatalogEntry(
            id: "fresh-book",
            title: "Fresh",
            author: "Author",
            description: "",
            coverAssetName: nil,
            totalDurationSeconds: 1,
            downloadSizeMB: 1,
            tracks: []
        )
        let persisted = Audiobook(
            title: "Persisted",
            folderName: "persisted",
            isFreeBook: true,
            catalogId: stale.id
        )
        context.insert(persisted)
        try context.save()
        var queue = [stale, fresh]

        let next = try FreeBookDownloadService.dequeueNextEligibleDownload(
            from: &queue,
            activeCatalogIds: [],
            modelContext: context
        )

        #expect(next?.id == fresh.id)
        #expect(queue.isEmpty)
    }

    @Test func queueLookupErrorPreservesCandidateAndIdentifiesIt() throws {
        struct LookupFailure: Error {}
        let candidate = makeSampleCatalogEntry()
        var queue = [candidate]

        do {
            _ = try FreeBookDownloadService.dequeueNextEligibleDownload(
                from: &queue,
                activeCatalogIds: [],
                modelContext: nil,
                admissionCheck: { _ in throw LookupFailure() }
            )
            Issue.record("Expected queue lookup to throw")
        } catch let error as FreeBookDownloadService.QueueIdentityLookupError {
            #expect(error.catalogId == candidate.id)
        }

        #expect(queue.map(\.id) == [candidate.id])
    }
}

private struct LegacyInjectedSaveFailure: Error {}
