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
        var errorMessage: String?

        var catalogID: String { request.catalogID }
        var metadata: Metadata { request.metadata }
        var target: Target { request.target }
    }

    struct Progress: Equatable, Sendable {
        let completed: Int
        let total: Int
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
                "This LibriVox book is no longer available in the local catalog."
            case .audiobookNotFound:
                "This audiobook is no longer in the library."
            }
        }
    }

    private(set) var entries: [String: Entry] = [:]

    typealias CompletionRemoval = @MainActor @Sendable (
        _ remove: @escaping @MainActor @Sendable () -> Void
    ) async -> Void

    private let executor: Executor
    private let completionRemoval: CompletionRemoval
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var attempts: [String: UInt64] = [:]

    init(
        executor: Executor,
        completionRemoval: @escaping CompletionRemoval = { remove in
            // Guarantee a render window for the completion phase; `Task.yield()` may not suspend.
            try? await Task.sleep(for: .milliseconds(500))
            remove()
        }
    ) {
        self.executor = executor
        self.completionRemoval = completionRemoval
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

        let attempt = (attempts[request.catalogID] ?? 0) &+ 1
        attempts[request.catalogID] = attempt
        entries[request.catalogID] = Entry(
            request: request,
            phase: .preparing,
            completedTracks: 0,
            totalTracks: 0,
            errorMessage: nil
        )

        tasks[request.catalogID] = makeTask(request: request, attempt: attempt)
        return true
    }

    /// Cancels the owned worker and does not release the catalog identity until the executor has
    /// returned from its cancellation cleanup.
    @discardableResult
    func cancel(catalogID: String) async -> Bool {
        guard var entry = entries[catalogID],
              entry.phase != .failed,
              entry.phase != .complete,
              let task = tasks[catalogID]
        else { return false }

        entry.phase = .cancelling
        entries[catalogID] = entry
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
              tasks[catalogID] == nil
        else { return false }

        let attempt = (attempts[catalogID] ?? 0) &+ 1
        attempts[catalogID] = attempt
        entry.phase = .preparing
        entry.completedTracks = 0
        entry.totalTracks = 0
        entry.errorMessage = nil
        entries[catalogID] = entry
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
        return true
    }

    /// Test/support seam for awaiting all currently owned work without exposing task ownership.
    func waitForAllWork() async {
        let currentTasks = Array(tasks.values)
        for task in currentTasks {
            await task.value
        }
    }

    private func makeTask(request: Request, attempt: UInt64) -> Task<Void, Never> {
        Task { [weak self, executor] in
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
        entries[catalogID] = entry
    }

    private func finishSuccess(for catalogID: String, attempt: UInt64) async {
        guard attempts[catalogID] == attempt, var entry = entries[catalogID] else { return }
        if entry.phase == .cancelling {
            tasks[catalogID] = nil
            entries[catalogID] = nil
            return
        }
        entry.phase = .complete
        entries[catalogID] = entry
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
    }

    private func finishFailure(_ error: Error, for catalogID: String, attempt: UInt64) {
        guard attempts[catalogID] == attempt, var entry = entries[catalogID] else { return }
        if entry.phase == .cancelling {
            tasks[catalogID] = nil
            entries[catalogID] = nil
            return
        }
        entry.phase = .failed
        entry.errorMessage = error.localizedDescription
        entries[catalogID] = entry
        tasks[catalogID] = nil
    }
}
