//
//  FreeBookDownloadServiceTests.swift
//  PagelessTests
//

import Testing
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

    private func makeSampleCatalogEntry() -> FreeBookCatalogEntry {
        FreeBookCatalogEntry(
            id: "test-book",
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
