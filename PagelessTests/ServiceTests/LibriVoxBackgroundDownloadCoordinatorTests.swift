//
//  LibriVoxBackgroundDownloadCoordinatorTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct LibriVoxBackgroundDownloadCoordinatorTests {
    @Test func byteCallbackPublishesFractionWithoutIncrementingTrack() {
        let job = makeJob(trackCount: 2)
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        let event = core.progressEvent(
            identity: identity(job, track: 0),
            totalBytesWritten: 25,
            totalBytesExpected: 100
        )

        #expect(event == .progress(
            catalogID: "book",
            attemptID: job.attemptID,
            completed: 0,
            total: 2,
            currentTrackFraction: 0.25
        ))
    }

    @Test func unknownExpectedByteCountPublishesZeroFraction() {
        let job = makeJob(trackCount: 2)
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        let event = core.progressEvent(
            identity: identity(job, track: 0),
            totalBytesWritten: 25,
            totalBytesExpected: NSURLSessionTransferSizeUnknown
        )

        #expect(event == .progress(
            catalogID: "book",
            attemptID: job.attemptID,
            completed: 0,
            total: 2,
            currentTrackFraction: 0
        ))
    }

    @Test func completedTrackPersistsThenSchedulesNext() throws {
        let job = makeJob(trackCount: 2)
        var persisted: [LibriVoxDownloadJob] = []
        let core = LibriVoxDownloadCoordinatorCore(
            jobs: [job],
            persist: { persisted.append($0) }
        )

        let result = try core.markTrackCompleted(identity: identity(job, track: 0))

        #expect(persisted.last?.completedIndexes == [0])
        #expect(result?.transition == .schedule(trackIndex: 1))
        #expect(result?.event == .progress(
            catalogID: "book",
            attemptID: job.attemptID,
            completed: 1,
            total: 2,
            currentTrackFraction: 0
        ))
    }

    @Test func finalTrackRequestsFinalization() throws {
        var job = makeJob(trackCount: 2)
        job.completedIndexes = [0]
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        let result = try core.markTrackCompleted(identity: identity(job, track: 1))

        #expect(result?.transition == .finalize)
    }

    @Test func lateCallbackFromOldAttemptIsIgnored() throws {
        let job = makeJob(trackCount: 1)
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])
        let oldIdentity = LibriVoxDownloadTaskIdentity(
            catalogID: job.catalogID,
            attemptID: UUID(),
            trackIndex: 0
        )

        #expect(core.progressEvent(
            identity: oldIdentity,
            totalBytesWritten: 1,
            totalBytesExpected: 2
        ) == nil)
        #expect(try core.markTrackCompleted(identity: oldIdentity) == nil)
    }

    @Test func retryWithoutPersistedFailureRestartsPreparation() {
        let core = LibriVoxDownloadCoordinatorCore(jobs: [])

        #expect(core.retryDisposition(catalogID: "book") == .restartPreparation)
    }

    @Test func retryWithPersistedFailureResumesStagedJob() {
        var job = makeJob(trackCount: 1)
        job.phase = .failed
        let core = LibriVoxDownloadCoordinatorCore(jobs: [job])

        #expect(core.retryDisposition(catalogID: "book") == .resume(job))
    }

    @Test func cancellationAfterPreparationBeforeManifestLeavesNoStagingOrManifest() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibriVoxDownloadManifestStore(rootURL: root)
        let beforeManifest = AsyncEvent()
        let gate = AsyncGate()
        let job = makeJob(trackCount: 1)
        let coordinator = LibriVoxBackgroundDownloadCoordinator(
            modelContext: try makeContext(),
            store: store,
            fileManager: .default,
            jobFactory: { _, _ in job },
            beforeManifestPersistence: {
                beforeManifest.signal()
                await gate.wait()
            }
        )

        let operation = Task {
            try? await coordinator.start(
                .init(catalogID: "book", metadata: .init(title: "Book"), target: .fresh),
                attemptID: job.attemptID
            )
        }
        await beforeManifest.wait()
        await coordinator.cancel(catalogID: "book", attemptID: job.attemptID)
        gate.open()
        await operation.value

        #expect(try store.loadAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging").path))
    }

    @Test func cancellationBeforeTaskSchedulingRemovesManifestAndStagingExactlyOnce() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibriVoxDownloadManifestStore(rootURL: root)
        let beforeScheduling = AsyncEvent()
        let gate = AsyncGate()
        let job = makeJob(trackCount: 1)
        var cancelledEvents = 0
        let coordinator = LibriVoxBackgroundDownloadCoordinator(
            modelContext: try makeContext(),
            store: store,
            fileManager: .default,
            jobFactory: { _, _ in job },
            beforeTaskScheduling: {
                beforeScheduling.signal()
                await gate.wait()
            }
        )
        coordinator.setEventSink { event in
            if case .cancelled = event { cancelledEvents += 1 }
        }

        let operation = Task {
            try? await coordinator.start(
                .init(catalogID: "book", metadata: .init(title: "Book"), target: .fresh),
                attemptID: job.attemptID
            )
        }
        await beforeScheduling.wait()
        await coordinator.cancel(catalogID: "book", attemptID: job.attemptID)
        await coordinator.cancel(catalogID: "book", attemptID: job.attemptID)
        gate.open()
        await operation.value

        #expect(cancelledEvents == 1)
        #expect(try store.loadAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging").appendingPathComponent(job.stagingFolderName).path))
    }

    @Test func malformedManifestIsQuarantinedAndDoesNotHaltOtherJobs() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibriVoxDownloadManifestStore(rootURL: root)
        let manifests = root.appendingPathComponent("Manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: manifests.appendingPathComponent("lost.json"))
        let coordinator = LibriVoxBackgroundDownloadCoordinator(
            modelContext: try makeContext(),
            store: store,
            fileManager: .default
        )

        #expect(coordinator.manifestRecoveryError == nil)
        #expect(try store.quarantinedFiles().count == 1)
    }

    @Test func finalizingPhaseDecodesAndRemainsDistinctFromDownloading() throws {
        var job = makeJob(trackCount: 1)
        job.phase = .finalizing
        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(LibriVoxDownloadJob.self, from: data)
        #expect(decoded.phase == .finalizing)
        #expect(decoded != job.withPhase(.downloading))
    }

    @Test func scheduleGuardRejectsCancelledAttemptAtEveryBoundary() {
        let job = makeJob(trackCount: 1)
        #expect(!LibriVoxBackgroundDownloadCoordinator.canSchedule(
            job: job,
            activeJob: job,
            cancelledAttempts: [job.attemptID]
        ))
        #expect(LibriVoxBackgroundDownloadCoordinator.canSchedule(
            job: job,
            activeJob: job,
            cancelledAttempts: []
        ))
    }

    @Test func freshFinalizationReplaysAfterDestinationMoveBeforeModelCommit() throws {
        let context = try makeContext()
        let book = LibriVoxBook(
            id: "book",
            title: "Jane Eyre",
            authorDisplay: "Charlotte Brontë",
            bookDescription: "",
            language: "English",
            totalTimeSecs: 60
        )
        context.insert(book)

        var job = makeJob(trackCount: 1)
        let destinationName = "replay-\(UUID().uuidString)"
        job.destinationFolderName = destinationName
        let destination = try FreeBookDownloadService.storageFolderURL(for: destinationName)
        defer { try? FileManager.default.removeItem(at: destination) }
        try Data("already-moved".utf8).write(
            to: destination.appendingPathComponent(job.tracks[0].storedFileName)
        )
        job.fileMetadata[0] = try LibriVoxDownloadService.fileMetadata(
            at: destination.appendingPathComponent(job.tracks[0].storedFileName)
        )
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-stage-\(UUID().uuidString)")

        let audiobook = try LibriVoxDownloadService.finalizeStagedFreshDownload(
            book: book,
            job: job,
            stagingFolderURL: staging,
            destinationFolderName: destinationName,
            modelContext: context,
            beforeCommit: {}
        )

        #expect(audiobook.folderName == destinationName)
        #expect(audiobook.isDownloaded)
        #expect(try Data(contentsOf: destination.appendingPathComponent(job.tracks[0].storedFileName)) == Data("already-moved".utf8))
    }

    @Test func afterFinalizationCommitCrashLeavesFreshManifestForNextProcessReplay() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibriVoxDownloadManifestStore(rootURL: root)
        let context = try makeContext()
        let book = LibriVoxBook(
            id: "book",
            title: "Jane Eyre",
            authorDisplay: "Charlotte Brontë",
            bookDescription: "",
            language: "English",
            totalTimeSecs: 60
        )
        context.insert(book)
        var job = makeJob(trackCount: 2)
        job.phase = .finalizing
        job.destinationFolderName = "crash-\(UUID().uuidString)"
        let destination = try FreeBookDownloadService.storageFolderURL(for: job.destinationFolderName!)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        for (index, track) in job.tracks.enumerated() {
            try Data("track-\(index)".utf8).write(to: destination.appendingPathComponent(track.storedFileName))
            job.fileMetadata[index] = try LibriVoxDownloadService.fileMetadata(
                at: destination.appendingPathComponent(track.storedFileName)
            )
        }
        job.completedIndexes = Set(job.tracks.indices)
        try store.save(job)

        let first = LibriVoxBackgroundDownloadCoordinator(
            modelContext: context,
            store: store,
            fileManager: .default,
            afterFinalizationCommit: { throw LibriVoxBackgroundDownloadCoordinator.FinalizationInterrupted() }
        )
        await first.reconcile()
        #expect(try store.loadAll() == [job])

        let second = LibriVoxBackgroundDownloadCoordinator(
            modelContext: context,
            store: store,
            fileManager: .default
        )
        await second.reconcile()
        #expect(try store.loadAll().isEmpty)
        let finalized = try context.fetch(FetchDescriptor<Audiobook>())
            .first { $0.catalogId == "book" }
        #expect(finalized?.isDownloaded == true)
        #expect(finalized?.tracks.count == 2)
    }

    @Test func existingFinalizationReplaysUsingDurableBackupsAfterProcessDeath() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibriVoxDownloadManifestStore(rootURL: root)
        let context = try makeContext()
        let folderName = "existing-replay-\(UUID().uuidString)"
        let audiobook = Audiobook(
            title: "Jane Eyre",
            folderName: folderName,
            isFreeBook: true,
            catalogId: "book",
            isDownloaded: false
        )
        for index in 0..<2 {
            let track = AudioTrack(
                title: "Old \(index)",
                originalFileName: "old-\(index).mp3",
                storedFileName: "\(index).mp3",
                orderIndex: index,
                duration: 60,
                audiobook: audiobook
            )
            audiobook.tracks.append(track)
            context.insert(track)
        }
        context.insert(audiobook)
        try context.save()
        let folder = try FreeBookDownloadService.storageFolderURL(for: folderName)
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<2 {
            try Data("new-\(index)".utf8).write(to: folder.appendingPathComponent("\(index).mp3"))
        }
        let backup = root.appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("durable", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        for index in 0..<2 {
            try Data("old-\(index)".utf8).write(to: backup.appendingPathComponent("\(index).mp3"))
        }
        let job = LibriVoxDownloadJob(
            catalogID: "book",
            attemptID: UUID(),
            title: "Jane Eyre",
            target: .existing(audiobookID: audiobook.id),
            stagingFolderName: "missing-stage",
            tracks: (0..<2).map { index in
                .init(
                    title: "New \(index)",
                    remoteURL: URL(string: "https://example.com/\(index).mp3")!,
                    durationSeconds: 60,
                    storedFileName: "\(index).mp3",
                    orderIndex: index
                )
            },
            completedIndexes: [0, 1],
            phase: .finalizing,
            lastError: nil,
            backupFolderName: "durable",
            fileMetadata: [
                0: try LibriVoxDownloadService.fileMetadata(at: folder.appendingPathComponent("0.mp3")),
                1: try LibriVoxDownloadService.fileMetadata(at: folder.appendingPathComponent("1.mp3"))
            ]
        )
        try store.save(job)

        let coordinator = LibriVoxBackgroundDownloadCoordinator(
            modelContext: context,
            store: store,
            fileManager: .default
        )
        await coordinator.reconcile()

        #expect(try store.loadAll().isEmpty)
        #expect(audiobook.isDownloaded)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(try Data(contentsOf: folder.appendingPathComponent("0.mp3")) == Data("new-0".utf8))
    }

    @Test func existingFinalizationRollbackRestoresPreexistingAudioAfterKillPoint() throws {
        let context = try makeContext()
        let folderName = "existing-\(UUID().uuidString)"
        let audiobook = Audiobook(
            title: "Jane Eyre",
            folderName: folderName,
            isFreeBook: true,
            catalogId: "book",
            isDownloaded: false
        )
        let track = AudioTrack(
            title: "Old",
            originalFileName: "old.mp3",
            storedFileName: "0.mp3",
            orderIndex: 0,
            duration: 60,
            audiobook: audiobook
        )
        audiobook.tracks.append(track)
        context.insert(audiobook)
        context.insert(track)
        try context.save()

        let folder = try FreeBookDownloadService.storageFolderURL(for: folderName)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("old-audio".utf8).write(to: folder.appendingPathComponent("0.mp3"))
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("existing-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Data("new-audio".utf8).write(to: staging.appendingPathComponent("0.mp3"))
        let backup = FileManager.default.temporaryDirectory
            .appendingPathComponent("existing-backup-(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: backup) }
        let job = LibriVoxDownloadJob(
            catalogID: "book",
            attemptID: UUID(),
            title: "Jane Eyre",
            target: .existing(audiobookID: audiobook.id),
            stagingFolderName: "stage",
            tracks: [
                .init(
                    title: "New",
                    remoteURL: URL(string: "https://example.com/0.mp3")!,
                    durationSeconds: 60,
                    storedFileName: "0.mp3",
                    orderIndex: 0
                )
            ],
            completedIndexes: [0],
            phase: .finalizing,
            lastError: nil,
            fileMetadata: [0: try LibriVoxDownloadService.fileMetadata(
                at: staging.appendingPathComponent("0.mp3")
            )]
        )

        #expect(throws: FinalizationTestError.self) {
            try LibriVoxDownloadService.finalizeStagedExistingDownload(
                audiobook: audiobook,
                job: job,
                stagingFolderURL: staging,
                backupFolderURL: backup,
                modelContext: context,
                beforeCommit: { throw FinalizationTestError() }
            )
        }
        #expect(try Data(contentsOf: folder.appendingPathComponent("0.mp3")) == Data("old-audio".utf8))
        #expect(!audiobook.isDownloaded)
    }

    private func identity(
        _ job: LibriVoxDownloadJob,
        track: Int
    ) -> LibriVoxDownloadTaskIdentity {
        .init(catalogID: job.catalogID, attemptID: job.attemptID, trackIndex: track)
    }

    private func makeJob(trackCount: Int) -> LibriVoxDownloadJob {
        .init(
            catalogID: "book",
            attemptID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Jane Eyre",
            target: .fresh,
            stagingFolderName: "stage",
            tracks: (0..<trackCount).map { index in
                .init(
                    title: "Track \(index)",
                    remoteURL: URL(string: "https://example.com/\(index).mp3")!,
                    durationSeconds: 60,
                    storedFileName: "\(index).mp3",
                    orderIndex: index
                )
            },
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, LibriVoxBook.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private extension LibriVoxDownloadJob {
    func withPhase(_ phase: Phase) -> Self {
        var copy = self
        copy.phase = phase
        return copy
    }
}

private struct FinalizationTestError: Error {}

@MainActor
private final class AsyncEvent {
    private var occurred = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !occurred else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func signal() {
        guard !occurred else { return }
        occurred = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

@MainActor
private final class AsyncGate {
    private var openState = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !openState else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        guard !openState else { return }
        openState = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}
