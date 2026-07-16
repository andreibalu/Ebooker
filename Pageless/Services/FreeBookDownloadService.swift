//
//  FreeBookDownloadService.swift
//  Pageless
//

import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class FreeBookDownloadService: FreeBookDownloading {
    nonisolated static let backgroundSessionIdentifier = "com.ebooker.freeBookDownloads"

    // MARK: - Published State

    var downloadProgress: [String: Double] = [:]
    var activeDownloads: Set<String> = []
    var downloadErrors: [String: String] = [:]

    // MARK: - Internal State

    private var sessionDelegate: SessionDelegate?
    private var backgroundSession: URLSession?
    private var taskContexts: [Int: DownloadTaskContext] = [:]
    private var bookDownloadState: [String: BookDownloadState] = [:]
    private var legacyJobs: [UUID: LegacyFreeBookDownloadJob] = [:]
    private var activeAttemptIDs: [String: UUID] = [:]
    private var pendingQueue: [FreeBookCatalogEntry] = []
    private var modelContext: ModelContext?
    private var queueHandoffRetryTask: Task<Void, Never>?
    private let manifestStore: LegacyFreeBookDownloadManifestStore
    private let afterFinalizationCommit: @MainActor () throws -> Void
    private(set) var manifestRecoveryError: String?

    struct DownloadTaskContext {
        let attemptID: UUID
        let trackIndex: Int
        let catalogId: String
        let trackEntry: FreeBookTrackEntry
        let folderName: String
    }

    struct BookDownloadState {
        let catalogEntry: FreeBookCatalogEntry
        let folderName: String
        var completedTracks: Int
        var totalTracks: Int
    }

    struct QueueIdentityLookupError: LocalizedError {
        let catalogId: String
        let underlyingError: Error

        var errorDescription: String? {
            underlyingError.localizedDescription
        }
    }

    init(
        manifestStore: LegacyFreeBookDownloadManifestStore? = nil,
        afterFinalizationCommit: @escaping @MainActor () throws -> Void = {}
    ) {
        self.manifestStore = manifestStore ?? LegacyFreeBookDownloadManifestStore()
        self.afterFinalizationCommit = afterFinalizationCommit
    }

    // MARK: - Configure

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        if backgroundSession != nil {
            guard manifestRecoveryError != nil else { return }
            restorePersistedJobs()
            return
        }
        let delegate = SessionDelegate(service: self)
        self.sessionDelegate = delegate
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.backgroundSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        restorePersistedJobs()
    }

    private func restorePersistedJobs() {
        do {
            let jobs = try manifestStore.loadAll()
            manifestRecoveryError = nil
            legacyJobs = Dictionary(jobs.map { ($0.attemptID, $0) }, uniquingKeysWith: { _, latest in latest })
            activeAttemptIDs.removeAll()
            for job in jobs where job.phase == .downloading {
                activeAttemptIDs[job.catalogID] = job.attemptID
                bookDownloadState[job.catalogID] = .init(
                    catalogEntry: job.catalogEntry,
                    folderName: job.folderName,
                    completedTracks: job.completedIndexes.count,
                    totalTracks: job.catalogEntry.tracks.count
                )
                activeDownloads.insert(job.catalogID)
                downloadProgress[job.catalogID] = progress(for: job)
            }
        } catch {
            manifestRecoveryError = error.localizedDescription
        }
    }

    /// Background-session entry point. Completion release must wait for both manifest restore
    /// and URLSession task reconciliation, including the fail-closed recovery decision.
    func restoreBackgroundSession(modelContext: ModelContext) async -> Bool {
        configure(modelContext: modelContext)
        guard manifestRecoveryError == nil else { return false }
        await reconcilePersistedJobs()
        return manifestRecoveryError == nil
    }

    // MARK: - Public API

    func startDownload(entry: FreeBookCatalogEntry) {
        guard manifestRecoveryError == nil else {
            downloadErrors[entry.id] = "Download recovery unavailable: \(manifestRecoveryError!)"
            return
        }
        let queuedCatalogIds = Set(pendingQueue.map(\.id))
        do {
            guard try Self.shouldAcceptDownload(
                catalogId: entry.id,
                activeCatalogIds: activeDownloads,
                queuedCatalogIds: queuedCatalogIds,
                modelContext: modelContext
            ) else { return }
        } catch {
            downloadErrors[entry.id] = "Could not check the library: \(error.localizedDescription)"
            return
        }

        guard checkDiskSpace(requiredMB: entry.downloadSizeMB) else {
            downloadErrors[entry.id] = "Not enough storage space. This book requires \(Int(entry.downloadSizeMB)) MB."
            return
        }

        if !activeDownloads.isEmpty {
            pendingQueue.append(entry)
            return
        }

        beginDownload(entry: entry)
    }

    func cancelDownload(catalogId: String) {
        let jobsToCancel = legacyJobs.values.filter { $0.catalogID == catalogId }
        let attemptIDs = Set(jobsToCancel.map(\.attemptID))
        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
        bookDownloadState.removeValue(forKey: catalogId)
        pendingQueue.removeAll { $0.id == catalogId }

        let tasksToCancel = taskContexts.filter { $0.value.catalogId == catalogId }
        tasksToCancel.keys.forEach { taskContexts.removeValue(forKey: $0) }
        activeAttemptIDs[catalogId] = nil

        guard let backgroundSession else {
            finishCancellation(catalogID: catalogId, jobs: jobsToCancel)
            return
        }
        Task { @MainActor [weak self] in
            let persistedTasks = await backgroundSession.allTasks
            persistedTasks.forEach { task in
                if Self.shouldCancelPersistedTask(
                    taskDescription: task.taskDescription,
                    catalogID: catalogId,
                    attemptIDs: attemptIDs,
                    jobs: jobsToCancel
                ) {
                    task.cancel()
                }
            }
            self?.finishCancellation(catalogID: catalogId, jobs: jobsToCancel)
        }
    }

    private func finishCancellation(
        catalogID: String,
        jobs: [LegacyFreeBookDownloadJob]
    ) {
        var cleanupErrors: [String] = []
        for job in jobs {
            do {
                try manifestStore.delete(attemptID: job.attemptID)
            } catch {
                cleanupErrors.append(error.localizedDescription)
            }
            if let folderURL = try? Self.storageFolderURL(for: job.folderName) {
                do {
                    try FileManager.default.removeItem(at: folderURL)
                } catch {
                    cleanupErrors.append(error.localizedDescription)
                }
            }
            legacyJobs[job.attemptID] = nil
        }
        activeAttemptIDs[catalogID] = nil
        if let firstError = cleanupErrors.first {
            let message = "Cancellation cleanup incomplete; retry required: \(firstError)"
            manifestRecoveryError = message
            downloadErrors[catalogID] = message
        }
    }

    static func shouldCancelPersistedTask(
        taskDescription: String?,
        catalogID: String,
        attemptIDs: Set<UUID>,
        jobs: [LegacyFreeBookDownloadJob]
    ) -> Bool {
        guard let taskDescription,
              let identity = LegacyFreeBookDownloadTaskIdentity(description: taskDescription),
              identity.catalogID == catalogID,
              attemptIDs.contains(identity.attemptID)
        else { return false }
        return jobs.contains { job in
            job.attemptID == identity.attemptID
                && job.catalogEntry.tracks.contains { $0.orderIndex == identity.trackIndex }
        }
    }

    // MARK: - Finalization

    @discardableResult
    func finalizeDownload(
        catalogEntry: FreeBookCatalogEntry,
        folderName: String,
        coverData: Data?,
        modelContext: ModelContext,
        saveModelContext: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Audiobook {
        if let match = try FreeBookIdentityService.match(
            catalogId: catalogEntry.id,
            modelContext: modelContext
        ) {
            switch match.classification {
            case .downloadedActive:
                let expected = Set(catalogEntry.tracks.map {
                    String(format: "%03d", $0.orderIndex + 1) + "-" + $0.fileName
                })
                if FreeBookIdentityService.hasCommittedAudioFiles(
                    match.audiobook,
                    expectedStoredFileNames: expected
                ) {
                    if folderName != match.audiobook.folderName,
                       let freshFolderURL = try? Self.storageFolderURL(for: folderName),
                       FileManager.default.fileExists(atPath: freshFolderURL.path(percentEncoded: false)) {
                        try? FileManager.default.removeItem(at: freshFolderURL)
                    }
                    return match.audiobook
                }
                if match.audiobook.tracks.isEmpty {
                    let freshFolderURL = try Self.storageFolderURL(for: folderName)
                    if FileManager.default.fileExists(atPath: freshFolderURL.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: freshFolderURL)
                    }
                    return match.audiobook
                }
                let tracks = catalogEntry.tracks.map { track in
                    let storedFileName = String(format: "%03d", track.orderIndex + 1) + "-" + track.fileName
                    let savedTrack = AudioTrack(
                        title: track.title,
                        originalFileName: track.fileName,
                        storedFileName: storedFileName,
                        orderIndex: track.orderIndex,
                        duration: track.durationSeconds
                    )
                    savedTrack.remoteURLString = track.downloadURL
                    return savedTrack
                }
                return try FreeBookIdentityService.promoteToDownloaded(
                    match.audiobook,
                    folderName: folderName,
                    title: catalogEntry.title,
                    author: catalogEntry.author,
                    coverArtData: coverData,
                    tracks: tracks,
                    modelContext: modelContext,
                    saveModelContext: saveModelContext
                )
            case .streamingActive, .archived:
                let tracks = catalogEntry.tracks.map { track in
                    let storedFileName = String(format: "%03d", track.orderIndex + 1) + "-" + track.fileName
                    let savedTrack = AudioTrack(
                        title: track.title,
                        originalFileName: track.fileName,
                        storedFileName: storedFileName,
                        orderIndex: track.orderIndex,
                        duration: track.durationSeconds
                    )
                    savedTrack.remoteURLString = track.downloadURL
                    return savedTrack
                }
                do {
                    return try FreeBookIdentityService.promoteToDownloaded(
                        match.audiobook,
                        folderName: folderName,
                        title: catalogEntry.title,
                        author: catalogEntry.author,
                        coverArtData: coverData,
                        tracks: tracks,
                        modelContext: modelContext,
                        saveModelContext: saveModelContext
                    )
                } catch {
                    let freshFolderURL = try Self.storageFolderURL(for: folderName)
                    try? FileManager.default.removeItem(at: freshFolderURL)
                    throw error
                }
            }
        }

        let audiobook = Audiobook(
            title: catalogEntry.title,
            author: catalogEntry.author,
            folderName: folderName,
            coverArtData: coverData,
            totalDuration: catalogEntry.totalDurationSeconds,
            isFreeBook: true,
            catalogId: catalogEntry.id
        )
        modelContext.insert(audiobook)

        for track in catalogEntry.tracks {
            let storedFileName = String(format: "%03d", track.orderIndex + 1) + "-" + track.fileName
            let savedTrack = AudioTrack(
                title: track.title,
                originalFileName: track.fileName,
                storedFileName: storedFileName,
                orderIndex: track.orderIndex,
                duration: track.durationSeconds,
                audiobook: audiobook
            )
            audiobook.tracks.append(savedTrack)
            modelContext.insert(savedTrack)
        }

        audiobook.totalDuration = audiobook.sortedTracks.reduce(0) { $0 + $1.duration }
        do {
            try saveModelContext(modelContext)
            return audiobook
        } catch {
            let insertedTracks = audiobook.tracks
            audiobook.tracks.removeAll()
            for track in insertedTracks {
                track.audiobook = nil
                modelContext.delete(track)
            }
            modelContext.delete(audiobook)
            let freshFolderURL = try Self.storageFolderURL(for: folderName)
            try? FileManager.default.removeItem(at: freshFolderURL)
            throw error
        }
    }

    /// Shared admission rule for direct starts and queueing. Downloaded identities block another
    /// download; streaming and archived identities remain eligible for in-place promotion.
    static func shouldAcceptDownload(
        catalogId: String,
        activeCatalogIds: Set<String>,
        queuedCatalogIds: Set<String>,
        modelContext: ModelContext?
    ) throws -> Bool {
        guard !activeCatalogIds.contains(catalogId), !queuedCatalogIds.contains(catalogId) else {
            return false
        }
        guard let modelContext else { return true }
        guard let match = try FreeBookIdentityService.match(
            catalogId: catalogId,
            modelContext: modelContext
        ) else {
            return true
        }
        return match.classification != .downloadedActive
    }

    /// Pops stale queue entries until one still has no active or persisted identity.
    static func dequeueNextEligibleDownload(
        from queue: inout [FreeBookCatalogEntry],
        activeCatalogIds: Set<String>,
        modelContext: ModelContext?,
        admissionCheck: ((FreeBookCatalogEntry) throws -> Bool)? = nil
    ) throws -> FreeBookCatalogEntry? {
        while let candidate = queue.first {
            let isEligible: Bool
            do {
                if let admissionCheck {
                    isEligible = try admissionCheck(candidate)
                } else {
                    isEligible = try shouldAcceptDownload(
                        catalogId: candidate.id,
                        activeCatalogIds: activeCatalogIds,
                        queuedCatalogIds: [],
                        modelContext: modelContext
                    )
                }
            } catch {
                throw QueueIdentityLookupError(catalogId: candidate.id, underlyingError: error)
            }

            queue.removeFirst()
            if isEligible {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Delegate Callbacks

    func handleDownloadFinished(taskId: Int, location: URL, taskDescription: String? = nil) {
        guard let context = resolveContext(taskId: taskId, taskDescription: taskDescription) else {
            try? FileManager.default.removeItem(at: location)
            return
        }

        do {
            guard let job = legacyJobs[context.attemptID],
                  let activeAttemptID = activeAttemptIDs[context.catalogId],
                  Self.acceptsCallback(context: context, job: job, activeAttemptID: activeAttemptID)
            else {
                try? FileManager.default.removeItem(at: location)
                taskContexts.removeValue(forKey: taskId)
                return
            }
            let folderURL = try Self.storageFolderURL(for: context.folderName)
            let storedFileName = String(format: "%03d", context.trackEntry.orderIndex + 1) + "-" + context.trackEntry.fileName
            let destinationURL = folderURL.appendingPathComponent(storedFileName)

            if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            taskContexts.removeValue(forKey: taskId)
            guard var job = legacyJobs[context.attemptID],
                  let activeAttemptID = activeAttemptIDs[context.catalogId],
                  Self.acceptsCallback(context: context, job: job, activeAttemptID: activeAttemptID)
            else {
                try? FileManager.default.removeItem(at: destinationURL)
                return
            }
            job.completedIndexes.insert(context.trackIndex)
            try manifestStore.save(job)
            legacyJobs[context.attemptID] = job
            handleTrackCompletion(catalogId: context.catalogId, job: job)
        } catch {
            failLegacyJob(context: context, error: error)
        }
    }

    func handleDownloadError(taskId: Int, error: Error, taskDescription: String? = nil) {
        guard let context = resolveContext(taskId: taskId, taskDescription: taskDescription) else { return }
        failLegacyJob(context: context, error: error)
    }

    private func failLegacyJob(context: DownloadTaskContext, error: Error) {
        let catalogId = context.catalogId
        downloadErrors[catalogId] = error.localizedDescription
        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
        bookDownloadState.removeValue(forKey: catalogId)

        let orphanTaskIds = taskContexts.compactMap { $0.value.catalogId == catalogId ? $0.key : nil }
        for id in orphanTaskIds { taskContexts.removeValue(forKey: id) }
        activeAttemptIDs[catalogId] = nil
        if var job = legacyJobs[context.attemptID] {
            job.phase = .failed
            job.lastError = error.localizedDescription
            do {
                try manifestStore.save(job)
                legacyJobs[context.attemptID] = job
            } catch {
                manifestRecoveryError = error.localizedDescription
            }
        }
        backgroundSession?.getAllTasks { tasks in
            for task in tasks where orphanTaskIds.contains(task.taskIdentifier) {
                task.cancel()
            }
        }
    }

    // MARK: - Private

    struct FinalizationInterrupted: Error {}

    private func resolveContext(
        taskId: Int,
        taskDescription: String?
    ) -> DownloadTaskContext? {
        if let context = taskContexts[taskId] {
            if let taskDescription,
               let identity = LegacyFreeBookDownloadTaskIdentity(description: taskDescription),
               (identity.attemptID != context.attemptID
                || identity.catalogID != context.catalogId
                || identity.trackIndex != context.trackIndex) {
                taskContexts.removeValue(forKey: taskId)
                return nil
            }
            guard let job = legacyJobs[context.attemptID],
                  let activeAttemptID = activeAttemptIDs[context.catalogId],
                  Self.acceptsCallback(context: context, job: job, activeAttemptID: activeAttemptID)
            else {
                taskContexts.removeValue(forKey: taskId)
                return nil
            }
            return context
        }
        guard let taskDescription,
              let identity = LegacyFreeBookDownloadTaskIdentity(description: taskDescription),
              let job = legacyJobs[identity.attemptID],
              let activeAttemptID = activeAttemptIDs[identity.catalogID],
              job.catalogID == identity.catalogID,
              let track = job.catalogEntry.tracks.first(where: { $0.orderIndex == identity.trackIndex })
        else { return nil }
        let context = DownloadTaskContext(
            attemptID: identity.attemptID,
            trackIndex: identity.trackIndex,
            catalogId: job.catalogID,
            trackEntry: track,
            folderName: job.folderName
        )
        guard Self.acceptsCallback(context: context, job: job, activeAttemptID: activeAttemptID) else {
            return nil
        }
        taskContexts[taskId] = context
        return context
    }

    static func acceptsCallback(
        context: DownloadTaskContext,
        job: LegacyFreeBookDownloadJob,
        activeAttemptID: UUID
    ) -> Bool {
        context.attemptID == activeAttemptID
            && context.attemptID == job.attemptID
            && context.catalogId == job.catalogID
            && job.phase == .downloading
            && job.catalogEntry.tracks.contains(where: {
                $0.orderIndex == context.trackIndex
                    && $0.id == context.trackEntry.id
                    && $0.fileName == context.trackEntry.fileName
                    && $0.downloadURL == context.trackEntry.downloadURL
                    && $0.durationSeconds == context.trackEntry.durationSeconds
            })
            && !job.completedIndexes.contains(context.trackIndex)
    }

    private func progress(for job: LegacyFreeBookDownloadJob) -> Double {
        guard !job.catalogEntry.tracks.isEmpty else { return 0 }
        return Double(job.completedIndexes.count) / Double(job.catalogEntry.tracks.count)
    }

    private func reconcilePersistedJobs() async {
        guard let backgroundSession else { return }
        let tasks = await backgroundSession.allTasks
        var scheduled: Set<LegacyFreeBookDownloadTaskIdentity> = []
        for task in tasks {
            guard let description = task.taskDescription,
                  let identity = LegacyFreeBookDownloadTaskIdentity(description: description),
                  let job = legacyJobs[identity.attemptID],
                  job.catalogID == identity.catalogID,
                  job.phase == .downloading,
                  job.catalogEntry.tracks.contains(where: { $0.orderIndex == identity.trackIndex })
            else {
                task.cancel()
                continue
            }
            scheduled.insert(identity)
            _ = resolveContext(taskId: task.taskIdentifier, taskDescription: description)
        }

        for job in Array(legacyJobs.values) where job.phase == .downloading {
            activeDownloads.insert(job.catalogID)
            downloadProgress[job.catalogID] = progress(for: job)
            bookDownloadState[job.catalogID] = .init(
                catalogEntry: job.catalogEntry,
                folderName: job.folderName,
                completedTracks: job.completedIndexes.count,
                totalTracks: job.catalogEntry.tracks.count
            )
            if job.completedIndexes.count == job.catalogEntry.tracks.count {
                completeBookDownload(
                    catalogId: job.catalogID,
                    state: bookDownloadState[job.catalogID]!,
                    job: job
                )
                continue
            }
            for track in job.catalogEntry.tracks where !job.completedIndexes.contains(track.orderIndex) {
                let identity = LegacyFreeBookDownloadTaskIdentity(
                    catalogID: job.catalogID,
                    attemptID: job.attemptID,
                    trackIndex: track.orderIndex
                )
                if scheduled.contains(identity) { continue }
                scheduleTask(track: track, job: job)
                scheduled.insert(identity)
            }
        }
    }

    private func scheduleTask(track: FreeBookTrackEntry, job: LegacyFreeBookDownloadJob) {
        guard let backgroundSession,
              let url = URL(string: track.downloadURL)
        else { return }
        let task = backgroundSession.downloadTask(with: url)
        task.taskDescription = LegacyFreeBookDownloadTaskIdentity(
            catalogID: job.catalogID,
            attemptID: job.attemptID,
            trackIndex: track.orderIndex
        ).description
        taskContexts[task.taskIdentifier] = DownloadTaskContext(
            attemptID: job.attemptID,
            trackIndex: track.orderIndex,
            catalogId: job.catalogID,
            trackEntry: track,
            folderName: job.folderName
        )
        task.resume()
    }

    private func isAlreadyCommitted(
        _ job: LegacyFreeBookDownloadJob,
        modelContext: ModelContext
    ) -> Bool {
        guard let match = try? FreeBookIdentityService.match(
            catalogId: job.catalogID,
            modelContext: modelContext
        ) else { return false }
        let expected = Set(job.catalogEntry.tracks.map {
            String(format: "%03d", $0.orderIndex + 1) + "-" + $0.fileName
        })
        return match.classification == .downloadedActive
            && FreeBookIdentityService.hasCommittedAudioFiles(
                match.audiobook,
                expectedStoredFileNames: expected
            )
    }

    private func beginDownload(entry: FreeBookCatalogEntry) {
        guard backgroundSession != nil else {
            downloadErrors[entry.id] = "Download service not ready."
            return
        }
        let folderName = UUID().uuidString
        let attemptID = UUID()
        let job = LegacyFreeBookDownloadJob(
            attemptID: attemptID,
            catalogEntry: entry,
            folderName: folderName,
            completedIndexes: [],
            phase: .downloading,
            lastError: nil
        )
        guard entry.tracks.allSatisfy({ URL(string: $0.downloadURL) != nil }) else {
            downloadErrors[entry.id] = "Download contains an invalid track URL."
            return
        }
        for (oldAttemptID, oldJob) in Array(legacyJobs) where oldJob.catalogID == entry.id {
            try? manifestStore.delete(attemptID: oldAttemptID)
            legacyJobs[oldAttemptID] = nil
        }
        do {
            try manifestStore.save(job)
        } catch {
            downloadErrors[entry.id] = "Could not prepare the download: \(error.localizedDescription)"
            return
        }
        legacyJobs[attemptID] = job
        activeAttemptIDs[entry.id] = attemptID
        activeDownloads.insert(entry.id)
        downloadProgress[entry.id] = 0.0
        downloadErrors.removeValue(forKey: entry.id)

        bookDownloadState[entry.id] = BookDownloadState(
            catalogEntry: entry,
            folderName: folderName,
            completedTracks: 0,
            totalTracks: entry.tracks.count
        )

        guard let backgroundSession else { return }
        for track in entry.tracks {
            guard let url = URL(string: track.downloadURL) else { continue }
            let task = backgroundSession.downloadTask(with: url)
            taskContexts[task.taskIdentifier] = DownloadTaskContext(
                attemptID: attemptID,
                trackIndex: track.orderIndex,
                catalogId: entry.id,
                trackEntry: track,
                folderName: folderName
            )
            task.taskDescription = LegacyFreeBookDownloadTaskIdentity(
                catalogID: entry.id,
                attemptID: attemptID,
                trackIndex: track.orderIndex
            ).description
            task.resume()
        }
    }

    private func handleTrackCompletion(catalogId: String, job: LegacyFreeBookDownloadJob) {
        guard var state = bookDownloadState[catalogId] else { return }
        state.completedTracks = job.completedIndexes.count
        bookDownloadState[catalogId] = state

        let progress = Double(state.completedTracks) / Double(state.totalTracks)
        downloadProgress[catalogId] = progress

        if state.completedTracks >= state.totalTracks {
            completeBookDownload(catalogId: catalogId, state: state, job: job)
        }
    }

    private func completeBookDownload(
        catalogId: String,
        state: BookDownloadState,
        job: LegacyFreeBookDownloadJob
    ) {
        guard let modelContext else { return }

        if isAlreadyCommitted(job, modelContext: modelContext) {
            do {
                try manifestStore.delete(attemptID: job.attemptID)
            } catch {
                manifestRecoveryError = error.localizedDescription
                return
            }
            legacyJobs[job.attemptID] = nil
            clearTaskContexts(catalogId: catalogId)
            activeAttemptIDs[catalogId] = nil
            clearActiveState(catalogId: catalogId)
            beginNextQueuedDownload()
            return
        }

        do {
            try finalizeDownload(
                catalogEntry: job.catalogEntry,
                folderName: state.folderName,
                coverData: nil,
                modelContext: modelContext
            )
            try afterFinalizationCommit()
            do {
                try manifestStore.delete(attemptID: job.attemptID)
            } catch {
                manifestRecoveryError = error.localizedDescription
                return
            }
            legacyJobs[job.attemptID] = nil
        } catch is FinalizationInterrupted {
            return
        } catch {
            downloadErrors[catalogId] = "Failed to save audiobook: \(error.localizedDescription)"
            var failed = job
            failed.phase = .failed
            failed.lastError = error.localizedDescription
            do {
                try manifestStore.save(failed)
                legacyJobs[job.attemptID] = failed
            } catch {
                manifestRecoveryError = error.localizedDescription
            }
            clearTaskContexts(catalogId: catalogId)
            activeAttemptIDs[catalogId] = nil
            return
        }

        clearTaskContexts(catalogId: catalogId)
        activeAttemptIDs[catalogId] = nil
        clearActiveState(catalogId: catalogId)

        beginNextQueuedDownload()
    }

    private func clearActiveState(catalogId: String) {
        activeDownloads.remove(catalogId)
        downloadProgress.removeValue(forKey: catalogId)
        bookDownloadState.removeValue(forKey: catalogId)
    }

    private func clearTaskContexts(catalogId: String) {
        taskContexts = taskContexts.filter { $0.value.catalogId != catalogId }
    }

    private func beginNextQueuedDownload() {
        queueHandoffRetryTask?.cancel()
        queueHandoffRetryTask = nil

        do {
            if let next = try Self.dequeueNextEligibleDownload(
                from: &pendingQueue,
                activeCatalogIds: activeDownloads,
                modelContext: modelContext
            ) {
                beginDownload(entry: next)
            }
        } catch {
            guard let candidate = pendingQueue.first else { return }
            let lookupError = error as? QueueIdentityLookupError
            let catalogId = lookupError?.catalogId ?? candidate.id
            downloadErrors[catalogId] = "Could not check the library: \(error.localizedDescription)"
            queueHandoffRetryTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                self.queueHandoffRetryTask = nil
                self.beginNextQueuedDownload()
            }
        }
    }

    private func checkDiskSpace(requiredMB: Double) -> Bool {
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = attrs[.systemFreeSize] as? Int64
        else {
            return true
        }
        let requiredBytes = Int64(requiredMB * 1_048_576)
        return freeSpace > Int64(Double(requiredBytes) * 1.1)
    }

    static func storageFolderURL(for folderName: String) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let libraryURL = applicationSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let audiobookFolderURL = libraryURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: audiobookFolderURL, withIntermediateDirectories: true)
        return audiobookFolderURL
    }
}

// MARK: - URLSession Delegate (separate NSObject)

private final class SessionDelegate: NSObject, URLSessionDownloadDelegate {
    private weak var service: FreeBookDownloadService?
    private let eventDrain = BackgroundEventDrain()

    init(service: FreeBookDownloadService) {
        self.service = service
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier
        let taskDescription = downloadTask.taskDescription
        let token = eventDrain.beginEvent()
        let drain = eventDrain
        let sessionIdentifier = session.configuration.identifier

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let error = URLError(.badServerResponse)
            Task { @MainActor [weak self] in
                defer { Self.finish(token: token, drain: drain, identifier: sessionIdentifier) }
                self?.service?.handleDownloadError(
                    taskId: taskId,
                    error: error,
                    taskDescription: taskDescription
                )
            }
            return
        }

        // Copy file to temp location before it gets cleaned up
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
        } catch {
            Task { @MainActor [weak self] in
                defer { Self.finish(token: token, drain: drain, identifier: sessionIdentifier) }
                self?.service?.handleDownloadError(
                    taskId: taskId,
                    error: error,
                    taskDescription: taskDescription
                )
            }
            return
        }

        Task { @MainActor [weak self] in
            defer { Self.finish(token: token, drain: drain, identifier: sessionIdentifier) }
            self?.service?.handleDownloadFinished(
                taskId: taskId,
                location: tempURL,
                taskDescription: taskDescription
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        let taskDescription = task.taskDescription
        let token = eventDrain.beginEvent()
        let drain = eventDrain
        let sessionIdentifier = session.configuration.identifier
        Task { @MainActor [weak self] in
            defer { Self.finish(token: token, drain: drain, identifier: sessionIdentifier) }
            self?.service?.handleDownloadError(
                taskId: taskId,
                error: error,
                taskDescription: taskDescription
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Track completion count used for progress instead of byte-level
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard eventDrain.markFinishEventsSeen() else { return }
        Self.requestCompletion(
            for: session.configuration.identifier ?? FreeBookDownloadService.backgroundSessionIdentifier,
            drain: eventDrain
        )
    }

    private static func finish(
        token: BackgroundEventDrain.Token,
        drain: BackgroundEventDrain?,
        identifier: String?
    ) {
        guard let drain, drain.finishEvent(token) else { return }
        requestCompletion(
            for: identifier ?? FreeBookDownloadService.backgroundSessionIdentifier,
            drain: drain
        )
    }

    private static func requestCompletion(for identifier: String, drain: BackgroundEventDrain) {
        Task { @MainActor in
            _ = drain.deliverIfReady {
                AppDelegate.shared?.requestBackgroundSessionCompletionHandler(for: identifier)?()
            }
        }
    }
}
