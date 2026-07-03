//
//  LibriVoxBackgroundDownloadCoordinator.swift
//  Pageless
//

import Foundation
import SwiftData

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
        identity: LibriVoxDownloadTaskIdentity
    ) throws -> LibriVoxDownloadCoordinatorCompletion? {
        guard var job = matchingJob(for: identity) else { return nil }
        job.completedIndexes.insert(identity.trackIndex)
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

    func remove(catalogID: String, attemptID: UUID) {
        guard jobs[catalogID]?.attemptID == attemptID else { return }
        jobs[catalogID] = nil
    }

    func job(catalogID: String, attemptID: UUID) -> LibriVoxDownloadJob? {
        guard let job = jobs[catalogID], job.attemptID == attemptID else { return nil }
        return job
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
              job.tracks.indices.contains(identity.trackIndex)
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
    private var eventSink: @MainActor (LibriVoxDownloadCoordinatorEvent) -> Void = { _ in }
    private var cancelledAttempts: Set<UUID> = []

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
            fileManager: .default
        )
    }

    init(
        modelContext: ModelContext,
        store: LibriVoxDownloadManifestStore,
        fileManager: FileManager
    ) {
        self.modelContext = modelContext
        self.store = store
        self.fileManager = fileManager
        let jobs = (try? store.loadAll()) ?? []
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

    func start(_ request: LibriVoxDownloadManager.Request, attemptID: UUID) async throws {
        guard core.jobs[request.catalogID] == nil else {
            throw CoordinatorError.jobAlreadyExists
        }
        let job = try await makeJob(request: request, attemptID: attemptID)
        try createStagingFolder(for: job)
        try store.save(job)
        core.replace(job)
        refreshRestoredJobs()
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
        guard let job = core.job(catalogID: catalogID, attemptID: attemptID) else { return }
        cancelledAttempts.insert(attemptID)
        let tasks = await session.allTasks
        tasks.filter { task in
            guard let description = task.taskDescription,
                  let identity = LibriVoxDownloadTaskIdentity(description: description)
            else { return false }
            return identity.catalogID == catalogID && identity.attemptID == attemptID
        }.forEach { $0.cancel() }
        try? store.delete(attemptID: attemptID)
        try? fileManager.removeItem(at: stagingFolderURL(for: job))
        core.remove(catalogID: catalogID, attemptID: attemptID)
        refreshRestoredJobs()
        eventSink(.cancelled(catalogID: catalogID, attemptID: attemptID))
    }

    func retry(_ request: LibriVoxDownloadManager.Request, attemptID: UUID) async throws {
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
            lastError: nil
        )
        try store.save(job)
        try store.delete(attemptID: oldJob.attemptID)
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
        ensureSession()
        let tasks = await session.allTasks
        var validIdentities: Set<LibriVoxDownloadTaskIdentity> = []
        for task in tasks {
            guard let description = task.taskDescription,
                  let identity = LibriVoxDownloadTaskIdentity(description: description),
                  core.job(catalogID: identity.catalogID, attemptID: identity.attemptID) != nil
            else {
                task.cancel()
                continue
            }
            validIdentities.insert(identity)
        }

        for originalJob in Array(core.jobs.values) {
            var job = originalJob
            job.completedIndexes = job.completedIndexes.filter {
                completedFileExists(job: job, trackIndex: $0)
            }
            if job.completedIndexes != originalJob.completedIndexes {
                try? store.save(job)
                core.replace(job)
            }
            guard job.phase != .failed else { continue }
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
                    )
                )
            }
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
                    )
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
        guard core.job(catalogID: job.catalogID, attemptID: job.attemptID) != nil,
              let index = job.tracks.indices.first(where: { !job.completedIndexes.contains($0) })
        else { return }
        let tasks = await session.allTasks
        let alreadyScheduled = tasks.contains { task in
            guard let description = task.taskDescription,
                  let identity = LibriVoxDownloadTaskIdentity(description: description)
            else { return false }
            return identity.catalogID == job.catalogID && identity.attemptID == job.attemptID
        }
        guard !alreadyScheduled else { return }

        let identity = LibriVoxDownloadTaskIdentity(
            catalogID: job.catalogID,
            attemptID: job.attemptID,
            trackIndex: index
        )
        let task = session.downloadTask(with: job.tracks[index].remoteURL)
        task.taskDescription = identity.description
        task.resume()
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
            guard let completion = try core.markTrackCompleted(identity: identity) else { return }
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
                    job: job,
                    stagingFolderURL: stagingFolderURL(for: job),
                    modelContext: modelContext,
                    beforeCommit: { [weak self] in
                        guard self?.cancelledAttempts.contains(job.attemptID) != true else {
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
                    job: job,
                    stagingFolderURL: stagingFolderURL(for: job),
                    modelContext: modelContext,
                    beforeCommit: { [weak self] in
                        guard self?.cancelledAttempts.contains(job.attemptID) != true else {
                            throw CancellationError()
                        }
                    }
                )
            }
            try store.delete(attemptID: job.attemptID)
            try? fileManager.removeItem(at: stagingFolderURL(for: job))
            core.remove(catalogID: job.catalogID, attemptID: job.attemptID)
            refreshRestoredJobs()
            eventSink(.completed(catalogID: job.catalogID, attemptID: job.attemptID))
        } catch is CancellationError {
            // Explicit cancellation owns cleanup and event delivery.
        } catch {
            fail(job, error: error)
        }
    }

    private func fail(_ job: LibriVoxDownloadJob, error: Error) {
        guard core.job(catalogID: job.catalogID, attemptID: job.attemptID) != nil,
              !cancelledAttempts.contains(job.attemptID)
        else { return }
        var failed = job
        failed.phase = .failed
        failed.lastError = error.localizedDescription
        try? store.save(failed)
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

    private func completedFileExists(job: LibriVoxDownloadJob, trackIndex: Int) -> Bool {
        guard job.tracks.indices.contains(trackIndex) else { return false }
        let url = completedFileURL(job: job, trackIndex: trackIndex)
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        else { return false }
        return (values.fileSize ?? 0) > 0
    }

    private func refreshRestoredJobs() {
        restoredJobs = core.jobs.values.sorted { $0.catalogID < $1.catalogID }
    }

    enum CoordinatorError: LocalizedError {
        case jobAlreadyExists

        var errorDescription: String? {
            switch self {
            case .jobAlreadyExists: "A download for this book already exists."
            }
        }
    }
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
        let durableTemporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibriVox-\(UUID().uuidString).download")
        do {
            try FileManager.default.moveItem(at: location, to: durableTemporaryURL)
        } catch {
            let description = downloadTask.taskDescription
            Task { @MainActor [weak self] in
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
        Task { @MainActor [weak self] in
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
        let description = task.taskDescription
        Task { @MainActor [weak self] in
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
        Task { @MainActor in
            AppDelegate.shared?.takeBackgroundSessionCompletionHandler(for: identifier)?()
        }
    }
}
