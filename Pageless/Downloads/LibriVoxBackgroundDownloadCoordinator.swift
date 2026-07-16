//
//  LibriVoxBackgroundDownloadCoordinator.swift
//  Pageless
//

import Foundation
import SwiftData

nonisolated final class BackgroundEventDrain: @unchecked Sendable {
    struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
        fileprivate let generation: UInt64

        fileprivate init(generation: UInt64) {
            self.generation = generation
        }
    }

    private let lock = NSLock()
    private var pending: Set<Token> = []
    private var finishEventsSeen = false
    private var releaseClaimed = false
    private var generation: UInt64 = 0

    func beginEvent() -> Token {
        lock.lock()
        if pending.isEmpty, releaseClaimed {
            generation &+= 1
            finishEventsSeen = false
            releaseClaimed = false
        }
        let token = Token(generation: generation)
        pending.insert(token)
        lock.unlock()
        return token
    }

    func finishEvent(_ token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard token.generation == generation, pending.remove(token) != nil else { return false }
        return canReleaseLocked()
    }

    func markFinishEventsSeen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finishEventsSeen else { return false }
        finishEventsSeen = true
        return canReleaseLocked()
    }

    func deliverIfReady(_ body: () -> Void) -> Bool {
        lock.lock()
        guard canReleaseLocked() else {
            lock.unlock()
            return false
        }
        releaseClaimed = true
        lock.unlock()
        body()
        return true
    }

    private func canReleaseLocked() -> Bool {
        guard finishEventsSeen, pending.isEmpty, !releaseClaimed else { return false }
        return true
    }
}

@MainActor
protocol LibriVoxDownloadCoordinating: AnyObject {
    var restoredJobs: [LibriVoxDownloadJob] { get }
    func setEventSink(_ sink: @escaping @MainActor (LibriVoxDownloadCoordinatorEvent) -> Void)
    func start(_ request: LibriVoxDownloadManager.Request, attemptID: UUID) async throws
    func cancel(catalogID: String, attemptID: UUID) async
    func retry(_ request: LibriVoxDownloadManager.Request, attemptID: UUID) async throws
    func reconcile() async
}

enum LibriVoxDownloadCoordinatorEvent: Equatable, Sendable {
    case progress(
        catalogID: String,
        attemptID: UUID,
        completed: Int,
        total: Int,
        currentTrackFraction: Double
    )
    case failed(catalogID: String, attemptID: UUID, message: String)
    case completed(catalogID: String, attemptID: UUID)
    case cancelled(catalogID: String, attemptID: UUID)
}

enum LibriVoxDownloadCoordinatorTransition: Equatable, Sendable {
    case schedule(trackIndex: Int)
    case finalize
}

struct LibriVoxDownloadCoordinatorCompletion: Equatable, Sendable {
    let event: LibriVoxDownloadCoordinatorEvent
    let transition: LibriVoxDownloadCoordinatorTransition
}

enum LibriVoxDownloadRetryDisposition: Equatable, Sendable {
    case restartPreparation
    case resume(LibriVoxDownloadJob)
}

@MainActor
final class LibriVoxDownloadCoordinatorCore {
    typealias Persist = (LibriVoxDownloadJob) throws -> Void

    private(set) var jobs: [String: LibriVoxDownloadJob]
    private let persist: Persist

    init(
        jobs: [LibriVoxDownloadJob],
        persist: @escaping Persist = { _ in }
    ) {
        self.jobs = Dictionary(jobs.map { ($0.catalogID, $0) }, uniquingKeysWith: { _, latest in latest })
        self.persist = persist
    }

    func progressEvent(
        identity: LibriVoxDownloadTaskIdentity,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    ) -> LibriVoxDownloadCoordinatorEvent? {
        guard let job = matchingJob(for: identity) else { return nil }
        let fraction: Double
        if totalBytesExpected > 0 {
            fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpected)))
        } else {
            fraction = 0
        }
        return .progress(
            catalogID: job.catalogID,
            attemptID: job.attemptID,
            completed: job.completedIndexes.count,
            total: job.tracks.count,
            currentTrackFraction: fraction
        )
    }

    func markTrackCompleted(
        identity: LibriVoxDownloadTaskIdentity,
        fileMetadata: LibriVoxDownloadFileMetadata = .init(
            byteCount: 1,
            sha256: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    ) throws -> LibriVoxDownloadCoordinatorCompletion? {
        guard var job = matchingJob(for: identity) else { return nil }
        job.completedIndexes.insert(identity.trackIndex)
        job.fileMetadata[identity.trackIndex] = fileMetadata
        job.phase = .downloading
        job.lastError = nil
        try persist(job)
        jobs[job.catalogID] = job

        let transition: LibriVoxDownloadCoordinatorTransition
        if let next = job.tracks.indices.first(where: { !job.completedIndexes.contains($0) }) {
            transition = .schedule(trackIndex: next)
        } else {
            transition = .finalize
        }
        return .init(
            event: .progress(
                catalogID: job.catalogID,
                attemptID: job.attemptID,
                completed: job.completedIndexes.count,
                total: job.tracks.count,
                currentTrackFraction: 0
            ),
            transition: transition
        )
    }

    func replace(_ job: LibriVoxDownloadJob) {
        jobs[job.catalogID] = job
    }

    func replaceAll(_ jobs: [LibriVoxDownloadJob]) {
        self.jobs = Dictionary(jobs.map { ($0.catalogID, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func remove(catalogID: String, attemptID: UUID) {
        guard jobs[catalogID]?.attemptID == attemptID else { return }
        jobs[catalogID] = nil
    }

    func job(catalogID: String, attemptID: UUID) -> LibriVoxDownloadJob? {
        guard let job = jobs[catalogID], job.attemptID == attemptID else { return nil }
        return job
    }

    func matches(_ identity: LibriVoxDownloadTaskIdentity) -> Bool {
        guard let job = matchingJob(for: identity) else { return false }
        return job.tracks[identity.trackIndex].orderIndex == identity.trackIndex
    }

    func retryDisposition(catalogID: String) -> LibriVoxDownloadRetryDisposition {
        guard let job = jobs[catalogID], job.phase == .failed else {
            return .restartPreparation
        }
        return .resume(job)
    }

    private func matchingJob(
        for identity: LibriVoxDownloadTaskIdentity
    ) -> LibriVoxDownloadJob? {
        guard let job = jobs[identity.catalogID],
              job.attemptID == identity.attemptID,
              job.tracks.indices.contains(identity.trackIndex),
              job.tracks[identity.trackIndex].orderIndex == identity.trackIndex
        else { return nil }
        return job
    }
}

@MainActor
final class LibriVoxBackgroundDownloadCoordinator: NSObject, LibriVoxDownloadCoordinating {
    static let sessionIdentifier = "andreibaludev.Pageless.librivoxDownloads"

    private(set) var restoredJobs: [LibriVoxDownloadJob]

    private let modelContext: ModelContext
    private let store: LibriVoxDownloadManifestStore
    private let fileManager: FileManager
    private let core: LibriVoxDownloadCoordinatorCore
    private let afterFinalizationCommit: @MainActor () throws -> Void
    private let jobFactory: (@MainActor (LibriVoxDownloadManager.Request, UUID) async throws -> LibriVoxDownloadJob)?
    private let beforeManifestPersistence: @MainActor () async throws -> Void
    private let beforeTaskScheduling: @MainActor () async throws -> Void
    nonisolated private let backgroundEventDrain = BackgroundEventDrain()
    private var eventSink: @MainActor (LibriVoxDownloadCoordinatorEvent) -> Void = { _ in }
    private var cancelledAttempts: Set<UUID> = []
    private(set) var manifestRecoveryError: String?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    convenience init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            store: LibriVoxDownloadManifestStore(),
            fileManager: .default,
            afterFinalizationCommit: {},
            jobFactory: nil,
            beforeManifestPersistence: {},
            beforeTaskScheduling: {}
        )
    }

    init(
        modelContext: ModelContext,
        store: LibriVoxDownloadManifestStore,
        fileManager: FileManager,
        afterFinalizationCommit: @escaping @MainActor () throws -> Void = {},
        jobFactory: (@MainActor (LibriVoxDownloadManager.Request, UUID) async throws -> LibriVoxDownloadJob)? = nil,
        beforeManifestPersistence: @escaping @MainActor () async throws -> Void = {},
        beforeTaskScheduling: @escaping @MainActor () async throws -> Void = {}
    ) {
        self.modelContext = modelContext
        self.store = store
        self.fileManager = fileManager
        self.afterFinalizationCommit = afterFinalizationCommit
        self.jobFactory = jobFactory
        self.beforeManifestPersistence = beforeManifestPersistence
        self.beforeTaskScheduling = beforeTaskScheduling
        let jobs: [LibriVoxDownloadJob]
        do {
            jobs = try store.loadAll()
            manifestRecoveryError = nil
        } catch {
            jobs = []
            manifestRecoveryError = error.localizedDescription
        }
        restoredJobs = jobs
        core = LibriVoxDownloadCoordinatorCore(jobs: jobs, persist: store.save)
        super.init()
    }

    func setEventSink(
        _ sink: @escaping @MainActor (LibriVoxDownloadCoordinatorEvent) -> Void
    ) {
        eventSink = sink
    }

    func ensureSession() {
        _ = session
    }

    /// Background-session entry point. Session completion waits for reconciliation, not merely
    /// lazy URLSession construction.
    func restoreBackgroundSession() async -> Bool {
        ensureSession()
        if manifestRecoveryError != nil {
            do {
                let jobs = try store.loadAll()
                core.replaceAll(jobs)
                restoredJobs = jobs
                manifestRecoveryError = nil
            } catch {
                manifestRecoveryError = error.localizedDescription
                return false
            }
        }
        await reconcile()
        return manifestRecoveryError == nil
    }

    func start(_ request: LibriVoxDownloadManager.Request, attemptID: UUID) async throws {
        guard manifestRecoveryError == nil else { throw CoordinatorError.manifestRecoveryFailed }
        guard core.jobs[request.catalogID] == nil else {
            throw CoordinatorError.jobAlreadyExists
        }
        try Task.checkCancellation()
        let job: LibriVoxDownloadJob
        if let jobFactory {
            job = try await jobFactory(request, attemptID)
        } else {
            job = try await makeJob(request: request, attemptID: attemptID)
        }
        try Task.checkCancellation()
        guard !cancelledAttempts.contains(attemptID) else { throw CancellationError() }
        try await beforeManifestPersistence()
        try Task.checkCancellation()
        guard !cancelledAttempts.contains(attemptID) else { throw CancellationError() }
        do {
            try createStagingFolder(for: job)
            try Task.checkCancellation()
            try store.save(job)
        } catch is CancellationError {
            try? fileManager.removeItem(at: stagingFolderURL(for: job))
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: stagingFolderURL(for: job))
            throw error
        }
        core.replace(job)
        refreshRestoredJobs()
        do {
            try await beforeTaskScheduling()
            try Task.checkCancellation()
            guard !cancelledAttempts.contains(attemptID) else { throw CancellationError() }
        } catch is CancellationError {
            await cancel(catalogID: job.catalogID, attemptID: job.attemptID)
            throw CancellationError()
        }
        eventSink(.progress(
            catalogID: job.catalogID,
            attemptID: job.attemptID,
            completed: 0,
            total: job.tracks.count,
            currentTrackFraction: 0
        ))
        await scheduleNextTrack(for: job)
    }

    func cancel(catalogID: String, attemptID: UUID) async {
        guard !cancelledAttempts.contains(attemptID) else { return }
        cancelledAttempts.insert(attemptID)
        guard let job = core.job(catalogID: catalogID, attemptID: attemptID) else { return }
        let tasks = await session.allTasks
        tasks.filter { task in
            guard let description = task.taskDescription,
                  let identity = LibriVoxDownloadTaskIdentity(description: description)
            else { return false }
            return identity.catalogID == catalogID && identity.attemptID == attemptID
        }.forEach { $0.cancel() }
        var cleanupError: Error?
        do {
            try store.delete(attemptID: attemptID)
        } catch {
            cleanupError = error
        }
        try? fileManager.removeItem(at: stagingFolderURL(for: job))
        try? fileManager.removeItem(at: backupFolderURL(for: job))
        if case .fresh = job.target,
           let destinationFolderName = job.destinationFolderName,
           (try? isAlreadyCommitted(job)) != true,
           let destinationURL = try? LibriVoxDownloadService.storageFolderURL(named: destinationFolderName) {
            try? fileManager.removeItem(at: destinationURL)
        }
        core.remove(catalogID: catalogID, attemptID: attemptID)
        refreshRestoredJobs()
        eventSink(.cancelled(catalogID: catalogID, attemptID: attemptID))
        if let cleanupError {
            manifestRecoveryError = cleanupError.localizedDescription
        }
    }

    func retry(_ request: LibriVoxDownloadManager.Request, attemptID: UUID) async throws {
        guard manifestRecoveryError == nil else { throw CoordinatorError.manifestRecoveryFailed }
        let oldJob: LibriVoxDownloadJob
        switch core.retryDisposition(catalogID: request.catalogID) {
        case .restartPreparation:
            try await start(request, attemptID: attemptID)
            return
        case .resume(let persistedJob):
            oldJob = persistedJob
        }
        var completed = oldJob.completedIndexes
        completed = completed.filter { completedFileExists(job: oldJob, trackIndex: $0) }
        let job = LibriVoxDownloadJob(
            catalogID: oldJob.catalogID,
            attemptID: attemptID,
            title: oldJob.title,
            target: oldJob.target,
            stagingFolderName: oldJob.stagingFolderName,
            tracks: oldJob.tracks,
            completedIndexes: completed,
            phase: .downloading,
            lastError: nil,
            destinationFolderName: oldJob.destinationFolderName,
            backupFolderName: oldJob.backupFolderName,
            fileMetadata: oldJob.fileMetadata
        )
        do {
            try store.save(job)
            try store.delete(attemptID: oldJob.attemptID)
        } catch {
            manifestRecoveryError = error.localizedDescription
            throw error
        }
        core.remove(catalogID: oldJob.catalogID, attemptID: oldJob.attemptID)
        core.replace(job)
        refreshRestoredJobs()
        eventSink(.progress(
            catalogID: job.catalogID,
            attemptID: job.attemptID,
            completed: job.completedIndexes.count,
            total: job.tracks.count,
            currentTrackFraction: 0
        ))
        if job.completedIndexes.count == job.tracks.count {
            await finalize(job)
        } else {
            await scheduleNextTrack(for: job)
        }
    }

    func reconcile() async {
        guard manifestRecoveryError == nil else { return }
        ensureSession()
        let tasks = await session.allTasks
        var validIdentities: Set<LibriVoxDownloadTaskIdentity> = []
        for task in tasks {
            guard let description = task.taskDescription,
                  let identity = LibriVoxDownloadTaskIdentity(description: description),
                  core.matches(identity)
            else {
                task.cancel()
                continue
            }
            validIdentities.insert(identity)
        }

        for originalJob in Array(core.jobs.values) {
            var job = originalJob
            if job.phase != .finalizing {
                job.completedIndexes = job.completedIndexes.filter {
                    completedFileExists(job: job, trackIndex: $0)
                }
                if job.completedIndexes != originalJob.completedIndexes {
                    do {
                        try store.save(job)
                    } catch {
                        manifestRecoveryError = error.localizedDescription
                        return
                    }
                    core.replace(job)
                }
            }
            guard job.phase != .failed else { continue }
            if job.phase == .finalizing {
                await finalize(job)
                continue
            }
            if job.completedIndexes.count == job.tracks.count {
                await finalize(job)
                continue
            }
            let hasTask = validIdentities.contains { identity in
                identity.catalogID == job.catalogID && identity.attemptID == job.attemptID
            }
            if !hasTask { await scheduleNextTrack(for: job) }
        }
        refreshRestoredJobs()
    }

    private func makeJob(
        request: LibriVoxDownloadManager.Request,
        attemptID: UUID
    ) async throws -> LibriVoxDownloadJob {
        let tracks: [LibriVoxDownloadTrack]
        let target: LibriVoxDownloadJob.Target
        switch request.target {
        case .fresh:
            let catalogID = request.catalogID
            var descriptor = FetchDescriptor<LibriVoxBook>(predicate: #Predicate { $0.id == catalogID })
            descriptor.fetchLimit = 1
            guard let book = try modelContext.fetch(descriptor).first else {
                throw LibriVoxDownloadManager.ManagerError.catalogBookNotFound
            }
            let fetched = try await LibriVoxDownloadService.prepareDownload(projectID: catalogID)
            try Task.checkCancellation()
            tracks = try fetched.enumerated().map { index, track in
                guard let url = URL(string: track.listenURL), !track.listenURL.isEmpty else {
                    throw LibriVoxDownloadError.invalidTrackURL(track.title)
                }
                return .init(
                    title: track.title.isEmpty ? "Track \(index + 1)" : track.title,
                    remoteURL: url,
                    durationSeconds: track.durationSeconds,
                    storedFileName: LibriVoxDownloadService.storedFileName(
                        title: track.title,
                        remoteURL: url,
                        index: index
                    ),
                    orderIndex: index
                )
            }
            try Task.checkCancellation()
            book.cachedTracks = fetched.enumerated().map { index, track in
                CachedLibriVoxTrack(
                    title: track.title,
                    listenURL: track.listenURL,
                    durationSeconds: track.durationSeconds,
                    orderIndex: index
                )
            }
            try modelContext.save()
            target = .fresh

        case .existing(let audiobookID):
            var descriptor = FetchDescriptor<Audiobook>(predicate: #Predicate { $0.id == audiobookID })
            descriptor.fetchLimit = 1
            guard let audiobook = try modelContext.fetch(descriptor).first else {
                throw LibriVoxDownloadManager.ManagerError.audiobookNotFound
            }
            tracks = try audiobook.sortedTracks.enumerated().map { index, track in
                guard let url = track.remoteURL else {
                    throw LibriVoxDownloadError.invalidTrackURL(track.title)
                }
                return .init(
                    title: track.title.isEmpty ? "Track \(index + 1)" : track.title,
                    remoteURL: url,
                    durationSeconds: track.duration,
                    storedFileName: LibriVoxDownloadService.storedFileName(
                        title: track.title,
                        remoteURL: url,
                        index: index
                    ),
                    orderIndex: index
                )
            }
            guard !tracks.isEmpty else { throw LibriVoxDownloadError.noTracks }
            target = .existing(audiobookID: audiobookID)
        }

        return .init(
            catalogID: request.catalogID,
            attemptID: attemptID,
            title: request.metadata.title,
            target: target,
            stagingFolderName: UUID().uuidString,
            tracks: tracks,
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
    }

    private func scheduleNextTrack(for job: LibriVoxDownloadJob) async {
        guard Self.canSchedule(
                  job: job,
                  activeJob: core.job(catalogID: job.catalogID, attemptID: job.attemptID),
                  cancelledAttempts: cancelledAttempts
              )
        else { return }
        let tasks = await session.allTasks
        guard let activeJob = core.job(catalogID: job.catalogID, attemptID: job.attemptID),
              Self.canSchedule(
            job: job,
            activeJob: activeJob,
            cancelledAttempts: cancelledAttempts
        ),
        let index = activeJob.tracks.indices.first(where: { !activeJob.completedIndexes.contains($0) }) else { return }
        let alreadyScheduled = tasks.contains { task in
            guard let description = task.taskDescription,
                  let identity = LibriVoxDownloadTaskIdentity(description: description)
            else { return false }
            return identity.catalogID == job.catalogID && identity.attemptID == job.attemptID
        }
        guard !alreadyScheduled else { return }

        let identity = LibriVoxDownloadTaskIdentity(
            catalogID: activeJob.catalogID,
            attemptID: activeJob.attemptID,
            trackIndex: index
        )
        let task = session.downloadTask(with: activeJob.tracks[index].remoteURL)
        task.taskDescription = identity.description
        guard Self.canSchedule(
            job: activeJob,
            activeJob: core.job(catalogID: activeJob.catalogID, attemptID: activeJob.attemptID),
            cancelledAttempts: cancelledAttempts
        ) else {
            task.cancel()
            return
        }
        task.resume()
    }

    static func canSchedule(
        job: LibriVoxDownloadJob,
        activeJob: LibriVoxDownloadJob?,
        cancelledAttempts: Set<UUID>
    ) -> Bool {
        activeJob?.attemptID == job.attemptID
            && activeJob?.phase == .downloading
            && !cancelledAttempts.contains(job.attemptID)
    }

    private func handleDownloadedFile(
        temporaryURL: URL,
        description: String?,
        statusCode: Int?
    ) async {
        guard let description,
              let identity = LibriVoxDownloadTaskIdentity(description: description),
              let job = core.job(catalogID: identity.catalogID, attemptID: identity.attemptID)
        else {
            try? fileManager.removeItem(at: temporaryURL)
            return
        }
        guard statusCode.map({ (200...299).contains($0) }) ?? true else {
            try? fileManager.removeItem(at: temporaryURL)
            fail(job, error: URLError(.badServerResponse))
            return
        }

        do {
            let destination = completedFileURL(job: job, trackIndex: identity.trackIndex)
            try fileManager.createDirectory(
                at: stagingFolderURL(for: job),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            let metadata = try LibriVoxDownloadService.fileMetadata(at: destination)
            guard let completion = try core.markTrackCompleted(
                identity: identity,
                fileMetadata: metadata
            ) else { return }
            refreshRestoredJobs()
            eventSink(completion.event)
            switch completion.transition {
            case .schedule:
                if let updated = core.job(catalogID: job.catalogID, attemptID: job.attemptID) {
                    await scheduleNextTrack(for: updated)
                }
            case .finalize:
                if let updated = core.job(catalogID: job.catalogID, attemptID: job.attemptID) {
                    await finalize(updated)
                }
            }
        } catch {
            fail(job, error: error)
        }
    }

    private func finalize(_ job: LibriVoxDownloadJob) async {
        guard !cancelledAttempts.contains(job.attemptID) else { return }
        do {
            if try isAlreadyCommitted(job) {
                do {
                    try store.delete(attemptID: job.attemptID)
                } catch {
                    manifestRecoveryError = error.localizedDescription
                    return
                }
                try? fileManager.removeItem(at: stagingFolderURL(for: job))
                try? fileManager.removeItem(at: backupFolderURL(for: job))
                core.remove(catalogID: job.catalogID, attemptID: job.attemptID)
                refreshRestoredJobs()
                eventSink(.completed(catalogID: job.catalogID, attemptID: job.attemptID))
                return
            }

            var finalizing = job
            finalizing.phase = .finalizing
            if case .fresh = finalizing.target, finalizing.destinationFolderName == nil {
                finalizing.destinationFolderName = UUID().uuidString
            }
            if case .existing = finalizing.target, finalizing.backupFolderName == nil {
                finalizing.backupFolderName = UUID().uuidString
            }
            if job.phase != .finalizing
                || job.destinationFolderName != finalizing.destinationFolderName
                || job.backupFolderName != finalizing.backupFolderName {
                try store.save(finalizing)
                core.replace(finalizing)
                refreshRestoredJobs()
            }

            switch job.target {
            case .fresh:
                let catalogID = job.catalogID
                var descriptor = FetchDescriptor<LibriVoxBook>(predicate: #Predicate { $0.id == catalogID })
                descriptor.fetchLimit = 1
                guard let book = try modelContext.fetch(descriptor).first else {
                    throw LibriVoxDownloadManager.ManagerError.catalogBookNotFound
                }
                _ = try LibriVoxDownloadService.finalizeStagedFreshDownload(
                    book: book,
                    job: finalizing,
                    stagingFolderURL: stagingFolderURL(for: finalizing),
                    destinationFolderName: finalizing.destinationFolderName,
                    modelContext: modelContext,
                    beforeCommit: { [weak self] in
                        guard self?.cancelledAttempts.contains(finalizing.attemptID) != true else {
                            throw CancellationError()
                        }
                    }
                )
            case .existing(let audiobookID):
                var descriptor = FetchDescriptor<Audiobook>(predicate: #Predicate { $0.id == audiobookID })
                descriptor.fetchLimit = 1
                guard let audiobook = try modelContext.fetch(descriptor).first else {
                    throw LibriVoxDownloadManager.ManagerError.audiobookNotFound
                }
                try LibriVoxDownloadService.finalizeStagedExistingDownload(
                    audiobook: audiobook,
                    job: finalizing,
                    stagingFolderURL: stagingFolderURL(for: finalizing),
                    backupFolderURL: backupFolderURL(for: finalizing),
                    modelContext: modelContext,
                    beforeCommit: { [weak self] in
                        guard self?.cancelledAttempts.contains(finalizing.attemptID) != true else {
                            throw CancellationError()
                        }
                    }
                )
            }
            try afterFinalizationCommit()
            do {
                try store.delete(attemptID: job.attemptID)
            } catch {
                manifestRecoveryError = error.localizedDescription
                return
            }
            try? fileManager.removeItem(at: stagingFolderURL(for: job))
            try? fileManager.removeItem(at: backupFolderURL(for: finalizing))
            core.remove(catalogID: job.catalogID, attemptID: job.attemptID)
            refreshRestoredJobs()
            eventSink(.completed(catalogID: job.catalogID, attemptID: job.attemptID))
        } catch is CancellationError {
            // Explicit cancellation owns cleanup and event delivery.
        } catch is FinalizationInterrupted {
            // Test/process-death seam: leave the finalizing manifest for reconciliation.
        } catch {
            fail(job, error: error)
        }
    }

    private func isAlreadyCommitted(_ job: LibriVoxDownloadJob) throws -> Bool {
        let expectedFileNames = Set(job.tracks.map(\.storedFileName))
        let audiobook: Audiobook?
        switch job.target {
        case .fresh:
            audiobook = try FreeBookIdentityService.match(
                catalogId: job.catalogID,
                modelContext: modelContext
            )?.audiobook
        case .existing(let audiobookID):
            var descriptor = FetchDescriptor<Audiobook>(predicate: #Predicate { $0.id == audiobookID })
            descriptor.fetchLimit = 1
            audiobook = try modelContext.fetch(descriptor).first
        }
        guard let audiobook else { return false }
        guard FreeBookIdentityService.hasCommittedAudioFiles(
            audiobook,
            expectedStoredFileNames: expectedFileNames,
            fileManager: fileManager
        ) else { return false }
        guard job.fileMetadata.count == job.tracks.count,
              let folderURL = try? LibriVoxDownloadService.storageFolderURL(named: audiobook.folderName)
        else { return false }
        return job.tracks.enumerated().allSatisfy { index, track in
            guard let expected = job.fileMetadata[index] else { return false }
            return LibriVoxDownloadService.fileMatchesMetadata(
                at: folderURL.appendingPathComponent(track.storedFileName),
                expected: expected,
                fileManager: fileManager
            )
        }
    }

    private func fail(_ job: LibriVoxDownloadJob, error: Error) {
        guard core.job(catalogID: job.catalogID, attemptID: job.attemptID) != nil,
              !cancelledAttempts.contains(job.attemptID)
        else { return }
        var failed = job
        failed.phase = .failed
        failed.lastError = error.localizedDescription
        do {
            try store.save(failed)
        } catch {
            manifestRecoveryError = error.localizedDescription
            return
        }
        core.replace(failed)
        refreshRestoredJobs()
        eventSink(.failed(
            catalogID: failed.catalogID,
            attemptID: failed.attemptID,
            message: error.localizedDescription
        ))
    }

    private func createStagingFolder(for job: LibriVoxDownloadJob) throws {
        try fileManager.createDirectory(
            at: stagingFolderURL(for: job),
            withIntermediateDirectories: true
        )
    }

    private func stagingFolderURL(for job: LibriVoxDownloadJob) -> URL {
        store.rootURL
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(job.stagingFolderName, isDirectory: true)
    }

    private func completedFileURL(job: LibriVoxDownloadJob, trackIndex: Int) -> URL {
        stagingFolderURL(for: job).appendingPathComponent(job.tracks[trackIndex].storedFileName)
    }

    private func backupFolderURL(for job: LibriVoxDownloadJob) -> URL {
        store.rootURL
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(job.backupFolderName ?? job.attemptID.uuidString, isDirectory: true)
    }

    private func completedFileExists(job: LibriVoxDownloadJob, trackIndex: Int) -> Bool {
        guard job.tracks.indices.contains(trackIndex) else { return false }
        let url = completedFileURL(job: job, trackIndex: trackIndex)
        guard let expected = job.fileMetadata[trackIndex] else { return false }
        return LibriVoxDownloadService.fileMatchesMetadata(
            at: url,
            expected: expected,
            fileManager: fileManager
        )
    }

    private func refreshRestoredJobs() {
        restoredJobs = core.jobs.values.sorted { $0.catalogID < $1.catalogID }
    }

    enum CoordinatorError: LocalizedError {
        case jobAlreadyExists
        case manifestRecoveryFailed

        var errorDescription: String? {
            switch self {
            case .jobAlreadyExists: "A download for this book already exists."
            case .manifestRecoveryFailed: "Download recovery is unavailable until the saved manifest is repaired."
            }
        }
    }

    struct FinalizationInterrupted: Error {}
}

extension LibriVoxBackgroundDownloadCoordinator: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let description = downloadTask.taskDescription
        Task { @MainActor [weak self] in
            guard let description,
                  let identity = LibriVoxDownloadTaskIdentity(description: description),
                  let event = self?.core.progressEvent(
                    identity: identity,
                    totalBytesWritten: totalBytesWritten,
                    totalBytesExpected: totalBytesExpectedToWrite
                  )
            else { return }
            self?.eventSink(event)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let token = backgroundEventDrain.beginEvent()
        let durableTemporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibriVox-\(UUID().uuidString).download")
        let drain = backgroundEventDrain
        do {
            try FileManager.default.moveItem(at: location, to: durableTemporaryURL)
        } catch {
            let description = downloadTask.taskDescription
            Task { @MainActor [weak self, drain] in
                defer {
                    if drain.finishEvent(token) {
                        Self.requestBackgroundCompletion(
                            for: Self.sessionIdentifier,
                            drain: drain
                        )
                    }
                }
                guard let description,
                      let identity = LibriVoxDownloadTaskIdentity(description: description),
                      let job = self?.core.job(
                        catalogID: identity.catalogID,
                        attemptID: identity.attemptID
                      )
                else { return }
                self?.fail(job, error: error)
            }
            return
        }
        let description = downloadTask.taskDescription
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor [weak self, drain] in
            defer {
                if drain.finishEvent(token) {
                    Self.requestBackgroundCompletion(
                        for: Self.sessionIdentifier,
                        drain: drain
                    )
                }
            }
            await self?.handleDownloadedFile(
                temporaryURL: durableTemporaryURL,
                description: description,
                statusCode: statusCode
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let token = backgroundEventDrain.beginEvent()
        let drain = backgroundEventDrain
        let description = task.taskDescription
        Task { @MainActor [weak self, drain] in
            defer {
                if drain.finishEvent(token) {
                    Self.requestBackgroundCompletion(
                        for: Self.sessionIdentifier,
                        drain: drain
                    )
                }
            }
            guard let description,
                  let identity = LibriVoxDownloadTaskIdentity(description: description),
                  let job = self?.core.job(
                    catalogID: identity.catalogID,
                    attemptID: identity.attemptID
                  )
            else { return }
            self?.fail(job, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier
            ?? "andreibaludev.Pageless.librivoxDownloads"
        guard backgroundEventDrain.markFinishEventsSeen() else { return }
        Self.requestBackgroundCompletion(for: identifier, drain: backgroundEventDrain)
    }

    nonisolated private static func requestBackgroundCompletion(
        for identifier: String,
        drain: BackgroundEventDrain
    ) {
        Task { @MainActor in
            _ = drain.deliverIfReady {
                AppDelegate.shared?.requestBackgroundSessionCompletionHandler(for: identifier)?()
            }
        }
    }
}
