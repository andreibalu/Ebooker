//
//  LibriVoxDownloadManagerTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxDownloadManagerTests {
    @Test func registersPreparingEntryBeforeExecutorStarts() async {
        let probe = RegistrationProbe()
        let executor = LibriVoxDownloadManager.Executor { request, _ in
            probe.observeRegistration(for: request.catalogID)
        }
        let manager = LibriVoxDownloadManager(executor: executor)
        probe.manager = manager

        let started = manager.start(request: request())
        await manager.waitForAllWork()

        #expect(started)
        #expect(probe.observedRegisteredEntry)
    }

    @Test func duplicateStartDoesNotCreateParallelExecutorWork() async {
        let gate = AsyncGate()
        let probe = InvocationProbe()
        let manager = LibriVoxDownloadManager(executor: .init { _, _ in
            probe.recordInvocation()
            await gate.wait()
        })

        let firstStarted = manager.start(request: request())
        let duplicateStarted = manager.start(request: request())
        await probe.firstInvocation.wait()

        #expect(firstStarted)
        #expect(!duplicateStarted)
        #expect(probe.invocationCount == 1)

        gate.open()
        await manager.waitForAllWork()
    }

    @Test(arguments: [
        LibriVoxDownloadManager.Target.fresh,
        .existing(audiobookID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    ])
    func reportsTrackProgressForFreshAndPromotionTargets(target: LibriVoxDownloadManager.Target) async {
        let gate = AsyncGate()
        let progressReported = AsyncEvent()
        let manager = LibriVoxDownloadManager(executor: .init { _, progress in
            progress(.init(completed: 2, total: 5))
            progressReported.signal()
            await gate.wait()
        })

        manager.start(request: request(target: target))
        await progressReported.wait()

        let entry = manager.entry(for: "catalog-1")
        #expect(entry?.target == target)
        #expect(entry?.phase == .downloading)
        #expect(entry?.completedTracks == 2)
        #expect(entry?.totalTracks == 5)

        gate.open()
        await manager.waitForAllWork()
    }

    @Test func progressSurvivesRequestingObjectRecreation() async {
        let gate = AsyncGate()
        let progressReported = AsyncEvent()
        let manager = LibriVoxDownloadManager(executor: .init { _, progress in
            progress(.init(completed: 1, total: 3))
            progressReported.signal()
            await gate.wait()
        })
        var requester: DownloadRequester? = DownloadRequester()

        requester?.start(on: manager, request: request())
        requester = nil
        await progressReported.wait()

        #expect(requester === nil)
        #expect(manager.entry(for: "catalog-1")?.completedTracks == 1)

        gate.open()
        await manager.waitForAllWork()
    }

    @Test func cancellationWaitsForCleanupAndBlocksImmediateRestart() async {
        let cleanupGate = AsyncGate()
        let probe = CancellationProbe()
        let manager = LibriVoxDownloadManager(executor: .init { _, _ in
            probe.workerStarted.signal()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                probe.cleanupStarted.signal()
                await cleanupGate.wait()
                probe.cleanupFinished = true
                throw error
            }
        })
        manager.start(request: request())
        await probe.workerStarted.wait()

        let cancellation = Task { await manager.cancel(catalogID: "catalog-1") }
        await probe.cleanupStarted.wait()

        #expect(manager.entry(for: "catalog-1")?.phase == .cancelling)
        #expect(!manager.start(request: request()))
        #expect(!probe.cleanupFinished)

        cleanupGate.open()
        let didCancel = await cancellation.value
        #expect(didCancel)
        #expect(probe.cleanupFinished)
        #expect(manager.entry(for: "catalog-1") == nil)
    }

    @Test func cancellationRemovesEntryWhenExecutorCleansUpAndReturnsNormally() async {
        let probe = NormalReturnCancellationProbe()
        let manager = LibriVoxDownloadManager(
            executor: .init { _, _ in
                probe.workerStarted.signal()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    probe.cleanupFinished = true
                    return
                }
            },
            completionRemoval: { _ in
                probe.completionRemovalCalled = true
            }
        )
        manager.start(request: request())
        await probe.workerStarted.wait()

        let didCancel = await manager.cancel(catalogID: "catalog-1")

        #expect(didCancel)
        #expect(probe.cleanupFinished)
        #expect(!probe.completionRemovalCalled)
        #expect(manager.entry(for: "catalog-1") == nil)
    }

    @Test func staleProgressFromCancelledAttemptCannotOverwriteRetry() async {
        let cleanupGate = AsyncGate()
        let secondGate = AsyncGate()
        let probe = AttemptProbe()
        let manager = LibriVoxDownloadManager(executor: .init { _, progress in
            let attempt = probe.beginAttempt(progress: progress)
            if attempt == 1 {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    probe.firstCleanupStarted.signal()
                    await cleanupGate.wait()
                    throw error
                }
            } else {
                progress(.init(completed: 1, total: 4))
                probe.secondProgressReported.signal()
                await secondGate.wait()
            }
        })
        manager.start(request: request())
        await probe.firstAttemptStarted.wait()
        let cancellation = Task { await manager.cancel(catalogID: "catalog-1") }
        await probe.firstCleanupStarted.wait()
        cleanupGate.open()
        _ = await cancellation.value

        #expect(manager.start(request: request()))
        await probe.secondProgressReported.wait()
        probe.sendStaleProgress(.init(completed: 99, total: 99))

        #expect(manager.entry(for: "catalog-1")?.completedTracks == 1)
        #expect(manager.entry(for: "catalog-1")?.totalTracks == 4)

        secondGate.open()
        await manager.waitForAllWork()
    }

    @Test func failurePersistsUntilRetryOrDismissal() async {
        let retryGate = AsyncGate()
        let probe = RetryProbe()
        let manager = LibriVoxDownloadManager(executor: .init { _, progress in
            let attempt = probe.beginAttempt()
            if attempt == 1 { throw TestFailure.offline }
            progress(.init(completed: 0, total: 2))
            probe.retryProgressReported.signal()
            await retryGate.wait()
        })
        manager.start(request: request())
        await manager.waitForAllWork()

        #expect(manager.entry(for: "catalog-1")?.phase == .failed)
        #expect(manager.entry(for: "catalog-1")?.errorMessage == "Offline for test")
        #expect(!manager.start(request: request()))
        #expect(manager.retry(catalogID: "catalog-1"))
        #expect(!manager.retry(catalogID: "catalog-1"))
        await probe.retryProgressReported.wait()
        #expect(manager.entry(for: "catalog-1")?.phase == .downloading)

        retryGate.open()
        await manager.waitForAllWork()

        let failingManager = LibriVoxDownloadManager(executor: .init { _, _ in
            throw TestFailure.offline
        })
        failingManager.start(request: request(catalogID: "dismiss-me"))
        await failingManager.waitForAllWork()
        #expect(failingManager.dismiss(catalogID: "dismiss-me"))
        #expect(failingManager.entry(for: "dismiss-me") == nil)
    }

    @Test func completeIsObservableAfterPersistenceBeforeGuardedRemoval() async {
        let persistenceGate = AsyncGate()
        let removalGate = AsyncGate()
        let probe = CompletionProbe()
        let manager = LibriVoxDownloadManager(
            executor: .init { _, progress in
                progress(.init(completed: 3, total: 3))
                probe.progressReported.signal()
                await persistenceGate.wait()
                probe.persistenceReturned = true
            },
            completionRemoval: { remove in
                probe.removalScheduled.signal()
                await removalGate.wait()
                remove()
                probe.removalFinished.signal()
            }
        )
        manager.start(request: request())
        await probe.progressReported.wait()

        #expect(!probe.persistenceReturned)
        #expect(manager.entry(for: "catalog-1") != nil)

        persistenceGate.open()
        await probe.removalScheduled.wait()

        #expect(probe.persistenceReturned)
        #expect(manager.entry(for: "catalog-1")?.phase == .complete)

        removalGate.open()
        await probe.removalFinished.wait()
        await manager.waitForAllWork()

        #expect(manager.entry(for: "catalog-1") == nil)
    }

    private func request(
        catalogID: String = "catalog-1",
        target: LibriVoxDownloadManager.Target = .fresh
    ) -> LibriVoxDownloadManager.Request {
        .init(
            catalogID: catalogID,
            metadata: .init(title: "The Book"),
            target: target
        )
    }
}

@MainActor
private final class DownloadRequester {
    func start(
        on manager: LibriVoxDownloadManager,
        request: LibriVoxDownloadManager.Request
    ) {
        manager.start(request: request)
    }
}

private enum TestFailure: LocalizedError {
    case offline

    var errorDescription: String? { "Offline for test" }
}

@MainActor
private final class RegistrationProbe {
    weak var manager: LibriVoxDownloadManager?
    private(set) var observedRegisteredEntry = false

    func observeRegistration(for catalogID: String) {
        observedRegisteredEntry = manager?.entry(for: catalogID)?.phase == .preparing
    }
}

@MainActor
private final class InvocationProbe {
    let firstInvocation = AsyncEvent()
    private(set) var invocationCount = 0

    func recordInvocation() {
        invocationCount += 1
        firstInvocation.signal()
    }
}

@MainActor
private final class CancellationProbe {
    let workerStarted = AsyncEvent()
    let cleanupStarted = AsyncEvent()
    var cleanupFinished = false
}

@MainActor
private final class NormalReturnCancellationProbe {
    let workerStarted = AsyncEvent()
    var cleanupFinished = false
    var completionRemovalCalled = false
}

@MainActor
private final class AttemptProbe {
    let firstAttemptStarted = AsyncEvent()
    let firstCleanupStarted = AsyncEvent()
    let secondProgressReported = AsyncEvent()
    private var attempt = 0
    private var firstProgress: (@MainActor @Sendable (LibriVoxDownloadManager.Progress) -> Void)?

    func beginAttempt(
        progress: @escaping @MainActor @Sendable (LibriVoxDownloadManager.Progress) -> Void
    ) -> Int {
        attempt += 1
        if attempt == 1 {
            firstProgress = progress
            firstAttemptStarted.signal()
        }
        return attempt
    }

    func sendStaleProgress(_ progress: LibriVoxDownloadManager.Progress) {
        firstProgress?(progress)
    }
}

@MainActor
private final class RetryProbe {
    let retryProgressReported = AsyncEvent()
    private var attempt = 0

    func beginAttempt() -> Int {
        attempt += 1
        return attempt
    }
}

@MainActor
private final class CompletionProbe {
    let progressReported = AsyncEvent()
    let removalScheduled = AsyncEvent()
    let removalFinished = AsyncEvent()
    var persistenceReturned = false
}

@MainActor
private final class AsyncEvent {
    private var hasOccurred = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !hasOccurred else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func signal() {
        guard !hasOccurred else { return }
        hasOccurred = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }
}

@MainActor
private final class AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }
}
