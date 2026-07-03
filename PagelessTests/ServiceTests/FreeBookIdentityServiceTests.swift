//
//  FreeBookIdentityServiceTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct FreeBookIdentityServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, LibriVoxBook.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeAudiobook(
        catalogId: String = "catalog-1",
        downloaded: Bool,
        archived: Bool,
        createdAt: Date
    ) -> Audiobook {
        let book = Audiobook(
            title: UUID().uuidString,
            folderName: UUID().uuidString,
            createdAt: createdAt,
            isFreeBook: true,
            catalogId: catalogId,
            isDownloaded: downloaded
        )
        book.isArchived = archived
        return book
    }

    private func makeLibriVoxBook(id: String = "catalog-1") -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: "Test Book",
            authorDisplay: "Test Author",
            bookDescription: "",
            language: "English",
            totalTimeSecs: 60
        )
    }

    @Test func lookupPrefersDownloadedThenStreamingThenArchived() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let archived = makeAudiobook(downloaded: true, archived: true, createdAt: Date(timeIntervalSince1970: 1))
        let streaming = makeAudiobook(downloaded: false, archived: false, createdAt: Date(timeIntervalSince1970: 2))
        let downloaded = makeAudiobook(downloaded: true, archived: false, createdAt: Date(timeIntervalSince1970: 3))
        context.insert(archived)
        context.insert(streaming)
        context.insert(downloaded)
        try context.save()

        let match = try FreeBookIdentityService.match(catalogId: "catalog-1", modelContext: context)

        #expect(match?.audiobook === downloaded)
        #expect(match?.classification == .downloadedActive)
    }

    @Test func lookupFallsBackToStreamingThenArchived() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let archived = makeAudiobook(downloaded: true, archived: true, createdAt: Date(timeIntervalSince1970: 1))
        let streaming = makeAudiobook(downloaded: false, archived: false, createdAt: Date(timeIntervalSince1970: 2))
        context.insert(archived)
        context.insert(streaming)
        try context.save()

        #expect(try FreeBookIdentityService.match(catalogId: "catalog-1", modelContext: context)?.audiobook === streaming)

        context.delete(streaming)
        try context.save()
        let archivedMatch = try FreeBookIdentityService.match(catalogId: "catalog-1", modelContext: context)
        #expect(archivedMatch?.audiobook === archived)
        #expect(archivedMatch?.classification == .archived)
    }

    @Test func lookupIgnoresOwnBooksWithCoincidentallyMatchingCatalogId() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let ownBook = Audiobook(title: "Own", folderName: "own", isFreeBook: false, catalogId: "catalog-1")
        context.insert(ownBook)
        try context.save()

        #expect(try FreeBookIdentityService.match(catalogId: "catalog-1", modelContext: context) == nil)
    }

    @Test func streamingInsertionReusesPersistedIdentity() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeAudiobook(downloaded: false, archived: false, createdAt: .now)
        context.insert(existing)
        try context.save()

        let result = try await StreamingLibraryService.addToLibrary(
            book: makeLibriVoxBook(),
            tracks: [],
            modelContext: context
        )

        #expect(result === existing)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }

    @Test func streamingInsertionUnarchivesPersistedIdentity() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let archived = makeAudiobook(downloaded: false, archived: true, createdAt: .now)
        archived.currentTime = 42
        context.insert(archived)
        try context.save()

        let result = try await StreamingLibraryService.addToLibrary(
            book: makeLibriVoxBook(),
            tracks: [],
            modelContext: context
        )

        #expect(result === archived)
        #expect(!result.isArchived)
        #expect(!result.isDownloaded)
        #expect(result.currentTime == 42)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }

    @Test func freshDownloadDuplicateReusesPersistedIdentityBeforeNetworkWork() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeAudiobook(downloaded: true, archived: false, createdAt: .now)
        context.insert(existing)
        try context.save()

        let result = try await LibriVoxDownloadService.downloadAndImport(
            book: makeLibriVoxBook(),
            tracks: [],
            modelContext: context,
            onProgress: { _, _ in }
        )

        #expect(result === existing)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }

    @Test func raceResolutionRemovesFreshFolderBeforeReusingPersistedIdentity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeAudiobook(downloaded: true, archived: false, createdAt: .now)
        context.insert(existing)
        try context.save()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: folder.appendingPathComponent("track.mp3"))

        let result = try LibriVoxDownloadService.finalizeDownloadedBook(
            book: makeLibriVoxBook(),
            folderName: folder.lastPathComponent,
            folderURL: folder,
            audioTracks: [],
            modelContext: context
        )

        #expect(result === existing)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test(arguments: [false, true])
    func downloadedFilesPromoteStreamingAndArchivedIdentity(archived: Bool) throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeAudiobook(downloaded: false, archived: archived, createdAt: .now)
        existing.currentTime = 73
        context.insert(existing)
        try context.save()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("audio".utf8).write(to: folder.appendingPathComponent("001-track.mp3"))
        let track = AudioTrack(
            title: "Track",
            originalFileName: "track.mp3",
            storedFileName: "001-track.mp3",
            orderIndex: 0,
            duration: 60
        )
        track.remoteURLString = "https://example.com/track.mp3"

        let result = try LibriVoxDownloadService.finalizeDownloadedBook(
            book: makeLibriVoxBook(),
            folderName: folder.lastPathComponent,
            folderURL: folder,
            audioTracks: [track],
            modelContext: context
        )

        #expect(result === existing)
        #expect(result.isDownloaded)
        #expect(!result.isArchived)
        #expect(result.currentTime == 73)
        #expect(result.folderName == folder.lastPathComponent)
        #expect(result.tracks.count == 1)
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
    }

    @Test func streamedPromotionFailureRollsBackTrackMetadataAndRemovesPartialFolder() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let audiobook = makeAudiobook(downloaded: false, archived: false, createdAt: .now)
        audiobook.folderName = UUID().uuidString
        audiobook.totalDuration = 30
        let first = AudioTrack(
            title: "First",
            originalFileName: "first-old.mp3",
            storedFileName: "first-old-local.mp3",
            orderIndex: 0,
            duration: 10
        )
        first.remoteURLString = "https://example.com/first.mp3"
        first.audiobook = audiobook
        let second = AudioTrack(
            title: "Second",
            originalFileName: "second-old.mp3",
            storedFileName: "second-old-local.mp3",
            orderIndex: 1,
            duration: 20
        )
        second.remoteURLString = "https://example.com/second.mp3"
        second.audiobook = audiobook
        audiobook.tracks = [first, second]
        context.insert(audiobook)
        context.insert(first)
        context.insert(second)
        try context.save()
        let probe = PromotionDownloadProbe()

        await #expect(throws: PromotionFailure.self) {
            try await LibriVoxDownloadService.downloadStreamedBook(
                audiobook: audiobook,
                modelContext: context,
                onProgress: { _, _ in },
                downloadToTemporaryFile: { _ in try await probe.download() }
            )
        }

        #expect(first.originalFileName == "first-old.mp3")
        #expect(first.storedFileName == "first-old-local.mp3")
        #expect(first.duration == 10)
        #expect(second.originalFileName == "second-old.mp3")
        #expect(second.storedFileName == "second-old-local.mp3")
        #expect(second.duration == 20)
        #expect(!audiobook.isDownloaded)
        #expect(audiobook.totalDuration == 30)

        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Audiobooks", isDirectory: true)
        .appendingPathComponent(audiobook.folderName, isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func freshDownloadLateCancellationCleansFolderWithoutInsertingAudiobook() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalogBook = makeLibriVoxBook()
        context.insert(catalogBook)
        let unrelated = Audiobook(title: "Original", folderName: "unrelated")
        context.insert(unrelated)
        try context.save()
        unrelated.title = "Unsaved edit"
        let foldersBefore = try audiobookFolderNames()
        let track = try makeAPITrack()

        let operation = Task<Void, Error> { @MainActor in
            _ = try await LibriVoxDownloadService.downloadAndImport(
                book: catalogBook,
                tracks: [track],
                modelContext: context,
                onProgress: { _, _ in },
                downloadToTemporaryFile: { _ in try temporaryAudioFile() },
                beforeCommit: { withUnsafeCurrentTask { $0?.cancel() } }
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await operation.value
        }
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).map(\.id) == [unrelated.id])
        #expect(unrelated.title == "Unsaved edit")
        #expect(try audiobookFolderNames() == foldersBefore)
    }

    @Test func streamedPromotionLateCancellationRollsBackBeforeApplyingMetadata() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let audiobook = makeAudiobook(downloaded: false, archived: false, createdAt: .now)
        audiobook.folderName = UUID().uuidString
        audiobook.totalDuration = 10
        let track = AudioTrack(
            title: "Track",
            originalFileName: "old.mp3",
            storedFileName: "old-local.mp3",
            orderIndex: 0,
            duration: 10
        )
        track.remoteURLString = "https://example.com/new.mp3"
        track.audiobook = audiobook
        audiobook.tracks = [track]
        context.insert(audiobook)
        context.insert(track)
        try context.save()

        let operation = Task { @MainActor in
            try await LibriVoxDownloadService.downloadStreamedBook(
                audiobook: audiobook,
                modelContext: context,
                onProgress: { _, _ in },
                downloadToTemporaryFile: { _ in try temporaryAudioFile() },
                beforeCommit: { withUnsafeCurrentTask { $0?.cancel() } }
            )
        }

        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
        #expect(track.originalFileName == "old.mp3")
        #expect(track.storedFileName == "old-local.mp3")
        #expect(track.duration == 10)
        #expect(!audiobook.isDownloaded)
        #expect(audiobook.totalDuration == 10)

        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Audiobooks", isDirectory: true)
        .appendingPathComponent(audiobook.folderName, isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func stagedPromotionLateCancellationRestoresMetadataAndRemovesMovedFiles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let audiobook = makeAudiobook(downloaded: false, archived: true, createdAt: .now)
        audiobook.folderName = UUID().uuidString
        audiobook.totalDuration = 10
        let track = AudioTrack(
            title: "Old Track",
            originalFileName: "old.mp3",
            storedFileName: "old-local.mp3",
            orderIndex: 0,
            duration: 10
        )
        track.remoteURLString = "https://example.com/new.mp3"
        track.audiobook = audiobook
        audiobook.tracks = [track]
        context.insert(audiobook)
        context.insert(track)
        try context.save()

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("StagedPromotion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: staging.appendingPathComponent("001-new.mp3"))
        defer { try? FileManager.default.removeItem(at: staging) }
        let job = LibriVoxDownloadJob(
            catalogID: "catalog-1",
            attemptID: UUID(),
            title: "Book",
            target: .existing(audiobookID: audiobook.id),
            stagingFolderName: staging.lastPathComponent,
            tracks: [
                .init(
                    title: "New Track",
                    remoteURL: URL(string: "https://example.com/new.mp3")!,
                    durationSeconds: 20,
                    storedFileName: "001-new.mp3"
                )
            ],
            completedIndexes: [0],
            phase: .downloading,
            lastError: nil
        )

        #expect(throws: CancellationError.self) {
            try LibriVoxDownloadService.finalizeStagedExistingDownload(
                audiobook: audiobook,
                job: job,
                stagingFolderURL: staging,
                modelContext: context,
                beforeCommit: { throw CancellationError() }
            )
        }

        #expect(track.title == "Old Track")
        #expect(track.originalFileName == "old.mp3")
        #expect(track.storedFileName == "old-local.mp3")
        #expect(track.duration == 10)
        #expect(!audiobook.isDownloaded)
        #expect(audiobook.isArchived)
        #expect(audiobook.totalDuration == 10)
        let destination = try audiobookFolderURL(named: audiobook.folderName)
            .appendingPathComponent("001-new.mp3")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func freshSaveFailureRemovesInsertedIdentityAndFolderSoRetryStartsFresh() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let catalogBook = makeLibriVoxBook()
        context.insert(catalogBook)
        let unrelated = Audiobook(title: "Original", folderName: "unrelated-save-failure")
        context.insert(unrelated)
        try context.save()
        unrelated.title = "Unsaved edit"
        let foldersBefore = try audiobookFolderNames()
        let track = try makeAPITrack()

        await #expect(throws: InjectedSaveFailure.self) {
            _ = try await LibriVoxDownloadService.downloadAndImport(
                book: catalogBook,
                tracks: [track],
                modelContext: context,
                onProgress: { _, _ in },
                downloadToTemporaryFile: { _ in try temporaryAudioFile() },
                beforeCommit: {},
                saveModelContext: { _ in throw InjectedSaveFailure() }
            )
        }

        #expect(try FreeBookIdentityService.match(catalogId: catalogBook.id, modelContext: context) == nil)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).map(\.id) == [unrelated.id])
        #expect(unrelated.title == "Unsaved edit")
        #expect(try audiobookFolderNames() == foldersBefore)

        let retried = try await LibriVoxDownloadService.downloadAndImport(
            book: catalogBook,
            tracks: [track],
            modelContext: context,
            onProgress: { _, _ in },
            downloadToTemporaryFile: { _ in try temporaryAudioFile() },
            beforeCommit: {}
        )
        defer {
            let folder = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Audiobooks", isDirectory: true)
            .appendingPathComponent(retried.folderName, isDirectory: true)
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
        #expect(retried.isDownloaded)
        let refetched = try FreeBookIdentityService.match(
            catalogId: catalogBook.id,
            modelContext: context
        )
        #expect(refetched?.audiobook.id == retried.id)
        #expect(refetched?.classification == .downloadedActive)
        let retryFolder = try audiobookFolderURL(named: refetched!.audiobook.folderName)
        #expect(FileManager.default.fileExists(atPath: retryFolder.path(percentEncoded: false)))
        #expect(unrelated.title == "Unsaved edit")
    }

    @Test func promotionSaveFailureRestoresPersistedIdentityAndFolderSoRetryCanPromote() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let audiobook = makeAudiobook(downloaded: false, archived: true, createdAt: .now)
        audiobook.folderName = UUID().uuidString
        audiobook.totalDuration = 10
        let track = AudioTrack(
            title: "Track",
            originalFileName: "old.mp3",
            storedFileName: "old-local.mp3",
            orderIndex: 0,
            duration: 10
        )
        track.remoteURLString = "https://example.com/new.mp3"
        track.audiobook = audiobook
        audiobook.tracks = [track]
        context.insert(audiobook)
        context.insert(track)
        let unrelated = Audiobook(title: "Original", folderName: "unrelated")
        context.insert(unrelated)
        try context.save()
        unrelated.title = "Unsaved edit"

        await #expect(throws: InjectedSaveFailure.self) {
            try await LibriVoxDownloadService.downloadStreamedBook(
                audiobook: audiobook,
                modelContext: context,
                onProgress: { _, _ in },
                downloadToTemporaryFile: { _ in try temporaryAudioFile() },
                beforeCommit: {},
                saveModelContext: { _ in throw InjectedSaveFailure() }
            )
        }

        #expect(!audiobook.isDownloaded)
        #expect(audiobook.isArchived)
        #expect(audiobook.totalDuration == 10)
        #expect(track.originalFileName == "old.mp3")
        #expect(track.storedFileName == "old-local.mp3")
        #expect(track.duration == 10)
        #expect(unrelated.title == "Unsaved edit")
        #expect(try FreeBookIdentityService.match(
            catalogId: "catalog-1",
            modelContext: context
        )?.classification == .archived)

        try await LibriVoxDownloadService.downloadStreamedBook(
            audiobook: audiobook,
            modelContext: context,
            onProgress: { _, _ in },
            downloadToTemporaryFile: { _ in try temporaryAudioFile() },
            beforeCommit: {}
        )
        #expect(audiobook.isDownloaded)
        let refetched = try FreeBookIdentityService.match(
            catalogId: "catalog-1",
            modelContext: context
        )
        #expect(refetched?.audiobook.id == audiobook.id)
        #expect(refetched?.classification == .downloadedActive)
        let retryFolder = try audiobookFolderURL(named: audiobook.folderName)
        #expect(FileManager.default.fileExists(atPath: retryFolder.path(percentEncoded: false)))
        #expect(unrelated.title == "Unsaved edit")
    }

    @Test func carPlayLegacyCatalogActionsPreserveIdentityClassification() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let downloaded = makeAudiobook(downloaded: true, archived: false, createdAt: .now)
        let streaming = makeAudiobook(downloaded: false, archived: false, createdAt: .now)
        let archived = makeAudiobook(downloaded: false, archived: true, createdAt: .now)

        #expect(CarPlayCoordinator.legacyCatalogAction(for: .init(
            audiobook: downloaded,
            classification: .downloadedActive
        )) == .playDownloaded)
        #expect(CarPlayCoordinator.legacyCatalogAction(for: .init(
            audiobook: streaming,
            classification: .streamingActive
        )) == .playStreaming)
        #expect(CarPlayCoordinator.legacyCatalogAction(for: .init(
            audiobook: archived,
            classification: .archived
        )) == .restoreArchivedStreaming)
        #expect(CarPlayCoordinator.legacyCatalogAction(for: nil) == .insertStreaming)
        #expect(!CarPlayCoordinator.LegacyCatalogAction.playDownloaded.requiresNetwork)
        #expect(CarPlayCoordinator.LegacyCatalogAction.playStreaming.requiresNetwork)
        #expect(CarPlayCoordinator.LegacyCatalogAction.restoreArchivedStreaming.requiresNetwork)
        #expect(CarPlayCoordinator.LegacyCatalogAction.insertStreaming.requiresNetwork)

        context.insert(archived)
        try context.save()
        let result = try CarPlayCoordinator.activateArchivedLegacyCatalogMatch(
            .init(audiobook: archived, classification: .archived),
            modelContext: context
        )
        #expect(result === archived)
        #expect(!archived.isArchived)
        #expect(!archived.isDownloaded)
    }

    private func makeAPITrack() throws -> LibriVoxAPITrack {
        let data = Data(#"{"id":"1","section_number":"1","title":"Track","playtime":"0:10","listen_url":"https://example.com/track.mp3"}"#.utf8)
        return try JSONDecoder().decode(LibriVoxAPITrack.self, from: data)
    }

    private func temporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("audio".utf8).write(to: url)
        return url
    }

    private func audiobookFolderNames() throws -> Set<String> {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let books = appSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        guard FileManager.default.fileExists(atPath: books.path(percentEncoded: false)) else {
            return []
        }
        return Set(try FileManager.default.contentsOfDirectory(atPath: books.path(percentEncoded: false)))
    }

    private func audiobookFolderURL(named folderName: String) throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Audiobooks", isDirectory: true)
        .appendingPathComponent(folderName, isDirectory: true)
    }
}

private enum PromotionFailure: Error {
    case injected
}

private struct InjectedSaveFailure: Error {}

@MainActor
private final class PromotionDownloadProbe {
    private var invocation = 0

    func download() async throws -> URL {
        invocation += 1
        guard invocation == 1 else { throw PromotionFailure.injected }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("audio".utf8).write(to: url)
        return url
    }
}
