//
//  LibriVoxDownloadManager.swift
//  Pageless
//

import Foundation
import Observation
import SwiftData

/// Owns every LibriVox download for the lifetime of the app process. Entries are keyed by
/// LibriVox project ID so navigation cannot duplicate or discard authoritative work state.
@MainActor
@Observable
final class LibriVoxDownloadManager {
    struct Metadata: Equatable, Sendable {
        let title: String
    }

    enum Target: Equatable, Sendable {
        case fresh
        case existing(audiobookID: UUID)
    }

    struct Request: Equatable, Sendable {
        let catalogID: String
        let metadata: Metadata
        let target: Target
    }

    enum Phase: Equatable, Sendable {
        case preparing
        case downloading
        case cancelling
        case failed
        case complete
    }

    struct Entry: Equatable, Sendable {
        let request: Request
        var phase: Phase
        var completedTracks: Int
        var totalTracks: Int
        var currentTrackFraction: Double = 0
        var errorMessage: String?

        var catalogID: String { request.catalogID }
        var metadata: Metadata { request.metadata }
        var target: Target { request.target }

        var progress: Double {
            guard totalTracks > 0 else { return 0 }
            let fraction = min(1, max(0, currentTrackFraction))
            return min(
                1,
                max(0, (Double(completedTracks) + fraction) / Double(totalTracks))
            )
        }
    }

    struct Progress: Equatable, Sendable {
        let completed: Int
        let total: Int
        let currentTrackFraction: Double

        init(completed: Int, total: Int, currentTrackFraction: Double = 0) {
            self.completed = completed
            self.total = total
            self.currentTrackFraction = currentTrackFraction
        }
    }

    struct Executor: Sendable {
        typealias Operation = @MainActor @Sendable (
            _ request: Request,
            _ progress: @escaping @MainActor @Sendable (Progress) -> Void
        ) async throws -> Void

        private let operation: Operation

        init(_ operation: @escaping Operation) {
            self.operation = operation
        }

        fileprivate func run(
            request: Request,
            progress: @escaping @MainActor @Sendable (Progress) -> Void
        ) async throws {
            try await operation(request, progress)
        }

        /// Production boundary. The executor resolves stable identities immediately before work,
        /// while tests can inject an entirely deterministic operation through `init(_:)`.
        static func live(modelContext: ModelContext) -> Executor {
            Executor { request, progress in
                switch request.target {
                case .fresh:
                    let catalogID = request.catalogID
                    var descriptor = FetchDescriptor<LibriVoxBook>(
                        predicate: #Predicate { $0.id == catalogID }
                    )
                    descriptor.fetchLimit = 1
                    guard let book = try modelContext.fetch(descriptor).first else {
                        throw ManagerError.catalogBookNotFound
                    }

                    let tracks = try await LibriVoxDownloadService.prepareDownload(
                        projectID: request.catalogID
                    )
                    progress(.init(completed: 0, total: tracks.count))
                    book.cachedTracks = tracks.enumerated().map { index, track in
                        CachedLibriVoxTrack(
                            title: track.title,
                            listenURL: track.listenURL,
                            durationSeconds: track.durationSeconds,
                            orderIndex: index
                        )
                    }
                    try modelContext.save()
                    _ = try await LibriVoxDownloadService.downloadAndImport(
                        book: book,
                        tracks: tracks,
                        modelContext: modelContext,
                        onProgress: { completed, total in
                            progress(.init(completed: completed, total: total))
                        }
                    )

                case .existing(let audiobookID):
                    var descriptor = FetchDescriptor<Audiobook>(
                        predicate: #Predicate { $0.id == audiobookID }
                    )
                    descriptor.fetchLimit = 1
                    guard let audiobook = try modelContext.fetch(descriptor).first else {
                        throw ManagerError.audiobookNotFound
                    }

                    progress(.init(completed: 0, total: audiobook.tracks.count))
                    try await LibriVoxDownloadService.downloadStreamedBook(
                        audiobook: audiobook,
                        modelContext: modelContext,
                        onProgress: { completed, total in
                            progress(.init(completed: completed, total: total))
                        }
                    )
                    audiobook.isArchived = false
                    try modelContext.save()
                }
            }
        }
    }

    enum ManagerError: LocalizedError {
        case catalogBookNotFound
        case audiobookNotFound

        var errorDescription: String? {
            switch self {
            case .catalogBookNotFound:
                "This book is no longer available from LibriVox."
            case .audiobookNotFound:
                "This audiobook is no longer in the library."
            }
        }
    }

    private(set) var entries: [String: Entry] = [:]

    typealias CompletionRemoval = @MainActor @Sendable (
        _ remove: @escaping @MainActor @Sendable () -> Void
    ) async -> Void

    private let executor: Executor?
    private let coordinator: LibriVoxDownloadCoordinating?
    private let activityController: DownloadLiveActivityControlling?
    private let isAppActive: @MainActor () -> Bool
    private let completionRemoval: CompletionRemoval
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var preparationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var attempts: [String: UInt64] = [:]
    @ObservationIgnored private var coordinatorAttempts: [String: UUID] = [:]

    init(
        executor: Executor,
        completionRemoval: @escaping CompletionRemoval = { remove in
            // Guarantee a render window for the completion phase; `Task.yield()` may not suspend.
            try? await Task.sleep(for: .milliseconds(500))
            remove()
        }
    ) {
        self.executor = executor
        coordinator = nil
        activityController = nil
        isAppActive = { true }
        self.completionRemoval = completionRemoval
    }

    init(
        coordinator: LibriVoxDownloadCoordinating,
        activityController: DownloadLiveActivityControlling,
        isAppActive: @escaping @MainActor () -> Bool = { true },
        completionRemoval: @escaping CompletionRemoval = { remove in
            try? await Task.sleep(for: .seconds(2))
            remove()
        }
    ) {
        executor = nil
        self.coordinator = coordinator
        self.activityController = activityController
        self.isAppActive = isAppActive
        self.completionRemoval = completionRemoval

        for job in coordinator.restoredJobs {
            let target: Target = switch job.target {
            case .fresh: .fresh
            case .existing(let audiobookID): .existing(audiobookID: audiobookID)
            }
            let phase: Phase = job.phase == .failed ? .failed : .downloading
            entries[job.catalogID] = Entry(
                request: .init(
                    catalogID: job.catalogID,
                    metadata: .init(title: job.title),
                    target: target
                ),
                phase: phase,
                completedTracks: job.completedIndexes.count,
                totalTracks: job.tracks.count,
                currentTrackFraction: 0,
                errorMessage: job.lastError
            )
            coordinatorAttempts[job.catalogID] = job.attemptID
        }
        coordinator.setEventSink { [weak self] event in
            self?.receive(event)
        }
        synchronizeActivity()
        Task { await coordinator.reconcile() }
    }

    func entry(for catalogID: String) -> Entry? {
        entries[catalogID]
    }

    /// Registers synchronously before the executor is allowed to begin preparation.
    @discardableResult
    func start(request: Request) -> Bool {
        guard entries[request.catalogID] == nil, tasks[request.catalogID] == nil else {
            return false
        }

        entries[request.catalogID] = Entry(
            request: request,
            phase: .preparing,
            completedTracks: 0,
            totalTracks: 0,
            currentTrackFraction: 0,
            errorMessage: nil
        )

        if let coordinator {
            let attemptID = UUID()
            coordinatorAttempts[request.catalogID] = attemptID
            synchronizeActivity()
            let task = Task { [weak self] in
                do {
                    try await coordinator.start(request, attemptID: attemptID)
                } catch is CancellationError {
                    self?.finishCoordinatorCancellation(
                        for: request.catalogID,
                        attemptID: attemptID
                    )
                } catch {
                    self?.finishCoordinatorFailure(
                        error,
                        for: request.catalogID,
                        attemptID: attemptID
                    )
                }
                self?.finishCoordinatorPreparation(
                    for: request.catalogID,
                    attemptID: attemptID
                )
            }
            preparationTasks[request.catalogID] = task
            return true
        }

        let attempt = (attempts[request.catalogID] ?? 0) &+ 1
        attempts[request.catalogID] = attempt
        tasks[request.catalogID] = makeTask(request: request, attempt: attempt)
        return true
    }

    /// Cancels the owned worker and does not release the catalog identity until the executor has
    /// returned from its cancellation cleanup.
    @discardableResult
    func cancel(catalogID: String) async -> Bool {
        if let coordinator,
           var entry = entries[catalogID],
           entry.phase != .failed,
           entry.phase != .complete,
           let attemptID = coordinatorAttempts[catalogID] {
            entry.phase = .cancelling
            entry.currentTrackFraction = 0
            entries[catalogID] = entry
            synchronizeActivity()
            preparationTasks[catalogID]?.cancel()
            await coordinator.cancel(catalogID: catalogID, attemptID: attemptID)
            await preparationTasks[catalogID]?.value
            guard coordinatorAttempts[catalogID] == attemptID else { return true }
            preparationTasks[catalogID] = nil
            coordinatorAttempts[catalogID] = nil
            entries[catalogID] = nil
            synchronizeActivity()
            return true
        }

        guard var entry = entries[catalogID],
              entry.phase != .failed,
              entry.phase != .complete,
              let task = tasks[catalogID]
        else { return false }

        entry.phase = .cancelling
        entries[catalogID] = entry
        synchronizeActivity()
        task.cancel()
        await task.value
        return true
    }

    /// Reuses the retained request and executor after failure. The failed entry continues to reserve
    /// its catalog ID until this new attempt has synchronously replaced it.
    @discardableResult
    func retry(catalogID: String) -> Bool {
        guard var entry = entries[catalogID],
              entry.phase == .failed,
              tasks[catalogID] == nil,
              preparationTasks[catalogID] == nil
        else { return false }

        entry.phase = .preparing
        entry.completedTracks = 0
        entry.totalTracks = 0
        entry.currentTrackFraction = 0
        entry.errorMessage = nil
        entries[catalogID] = entry

        if let coordinator {
            let attemptID = UUID()
            coordinatorAttempts[catalogID] = attemptID
            synchronizeActivity()
            let task = Task { [weak self] in
                do {
                    try await coordinator.retry(entry.request, attemptID: attemptID)
                } catch is CancellationError {
                    self?.finishCoordinatorCancellation(
                        for: catalogID,
                        attemptID: attemptID
                    )
                } catch {
                    self?.finishCoordinatorFailure(error, for: catalogID, attemptID: attemptID)
                }
                self?.finishCoordinatorPreparation(
                    for: catalogID,
                    attemptID: attemptID
                )
            }
            preparationTasks[catalogID] = task
            return true
        }

        let attempt = (attempts[catalogID] ?? 0) &+ 1
        attempts[catalogID] = attempt
        tasks[catalogID] = makeTask(request: entry.request, attempt: attempt)
        return true
    }

    /// Failed work is intentionally sticky; dismissal is the explicit release path.
    @discardableResult
    func dismiss(catalogID: String) -> Bool {
        guard entries[catalogID]?.phase == .failed, tasks[catalogID] == nil else {
            return false
        }
        entries[catalogID] = nil
        if let coordinator, let attemptID = coordinatorAttempts.removeValue(forKey: catalogID) {
            Task { await coordinator.cancel(catalogID: catalogID, attemptID: attemptID) }
        }
        synchronizeActivity()
        return true
    }

    /// Test/support seam for awaiting all currently owned work without exposing task ownership.
    func waitForAllWork() async {
        let currentTasks = Array(tasks.values)
        for task in currentTasks {
            await task.value
        }
        let currentPreparationTasks = Array(preparationTasks.values)
        for task in currentPreparationTasks {
            await task.value
        }
    }

    private func makeTask(request: Request, attempt: UInt64) -> Task<Void, Never> {
        Task { [weak self, executor] in
            guard let executor else { return }
            do {
                try await executor.run(request: request) { [weak self] progress in
                    self?.receive(progress, for: request.catalogID, attempt: attempt)
                }
                await self?.finishSuccess(for: request.catalogID, attempt: attempt)
            } catch {
                self?.finishFailure(error, for: request.catalogID, attempt: attempt)
            }
        }
    }

    private func receive(_ progress: Progress, for catalogID: String, attempt: UInt64) {
        guard attempts[catalogID] == attempt,
              var entry = entries[catalogID],
              entry.phase != .cancelling,
              entry.phase != .failed,
              entry.phase != .complete
        else { return }
        entry.phase = .downloading
        entry.completedTracks = max(0, progress.completed)
        entry.totalTracks = max(0, progress.total)
        entry.currentTrackFraction = min(1, max(0, progress.currentTrackFraction))
        entries[catalogID] = entry
        synchronizeActivity()
    }

    private func finishSuccess(for catalogID: String, attempt: UInt64) async {
        guard attempts[catalogID] == attempt, var entry = entries[catalogID] else { return }
        if entry.phase == .cancelling {
            tasks[catalogID] = nil
            entries[catalogID] = nil
            synchronizeActivity()
            return
        }
        entry.phase = .complete
        entries[catalogID] = entry
        synchronizeActivity()
        await completionRemoval { [weak self] in
            self?.removeCompletedEntry(for: catalogID, attempt: attempt)
        }
        guard attempts[catalogID] == attempt else { return }
        tasks[catalogID] = nil
    }

    private func removeCompletedEntry(for catalogID: String, attempt: UInt64) {
        guard attempts[catalogID] == attempt,
              entries[catalogID]?.phase == .complete
        else { return }
        entries[catalogID] = nil
        synchronizeActivity()
    }

    private func finishFailure(_ error: Error, for catalogID: String, attempt: UInt64) {
        guard attempts[catalogID] == attempt, var entry = entries[catalogID] else { return }
        if entry.phase == .cancelling {
            tasks[catalogID] = nil
            entries[catalogID] = nil
            synchronizeActivity()
            return
        }
        entry.phase = .failed
        entry.errorMessage = error.localizedDescription
        entries[catalogID] = entry
        tasks[catalogID] = nil
        synchronizeActivity()
    }

    func applicationDidBecomeActive() {
        synchronizeActivity()
    }

    private func receive(_ event: LibriVoxDownloadCoordinatorEvent) {
        switch event {
        case let .progress(catalogID, attemptID, completed, total, currentTrackFraction):
            guard coordinatorAttempts[catalogID] == attemptID,
                  var entry = entries[catalogID],
                  entry.phase != .cancelling
            else { return }
            entry.phase = .downloading
            entry.completedTracks = max(0, completed)
            entry.totalTracks = max(0, total)
            entry.currentTrackFraction = min(1, max(0, currentTrackFraction))
            entry.errorMessage = nil
            entries[catalogID] = entry
            synchronizeActivity()

        case let .failed(catalogID, attemptID, message):
            guard coordinatorAttempts[catalogID] == attemptID,
                  var entry = entries[catalogID],
                  entry.phase != .cancelling
            else { return }
            entry.phase = .failed
            entry.currentTrackFraction = 0
            entry.errorMessage = message
            entries[catalogID] = entry
            synchronizeActivity()

        case let .completed(catalogID, attemptID):
            guard coordinatorAttempts[catalogID] == attemptID else { return }
            Task { [weak self] in
                await self?.finishCoordinatorSuccess(for: catalogID, attemptID: attemptID)
            }

        case let .cancelled(catalogID, attemptID):
            guard coordinatorAttempts[catalogID] == attemptID else { return }
            coordinatorAttempts[catalogID] = nil
            entries[catalogID] = nil
            synchronizeActivity()
        }
    }

    private func finishCoordinatorFailure(
        _ error: Error,
        for catalogID: String,
        attemptID: UUID
    ) {
        receive(.failed(
            catalogID: catalogID,
            attemptID: attemptID,
            message: error.localizedDescription
        ))
    }

    private func finishCoordinatorCancellation(for catalogID: String, attemptID: UUID) {
        guard coordinatorAttempts[catalogID] == attemptID,
              entries[catalogID]?.phase == .cancelling
        else { return }
        entries[catalogID] = nil
        coordinatorAttempts[catalogID] = nil
        preparationTasks[catalogID] = nil
        synchronizeActivity()
    }

    private func finishCoordinatorPreparation(for catalogID: String, attemptID: UUID) {
        guard coordinatorAttempts[catalogID] == attemptID else { return }
        preparationTasks[catalogID] = nil
    }

    private func finishCoordinatorSuccess(for catalogID: String, attemptID: UUID) async {
        guard coordinatorAttempts[catalogID] == attemptID, var entry = entries[catalogID] else {
            return
        }
        entry.phase = .complete
        entry.currentTrackFraction = 0
        entry.completedTracks = entry.totalTracks
        entries[catalogID] = entry
        synchronizeActivity()
        await completionRemoval { [weak self] in
            guard self?.coordinatorAttempts[catalogID] == attemptID else { return }
            self?.coordinatorAttempts[catalogID] = nil
            self?.entries[catalogID] = nil
            self?.synchronizeActivity()
        }
    }

    private func synchronizeActivity() {
        guard let activityController else { return }
        let snapshot = DownloadActivitySnapshot.aggregate(entries: Array(entries.values))
        let appIsActive = isAppActive()
        Task {
            await activityController.synchronize(
                snapshot: snapshot,
                appIsActive: appIsActive
            )
        }
    }
}
