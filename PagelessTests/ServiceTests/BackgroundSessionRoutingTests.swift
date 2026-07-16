//
//  BackgroundSessionRoutingTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

@MainActor
struct BackgroundSessionRoutingTests {
    @Test func handlersAreConsumedOnlyByMatchingSessionIdentifier() {
        let registry = BackgroundSessionCompletionRegistry()
        var legacyCalls = 0
        var libriVoxCalls = 0
        registry.store({ legacyCalls += 1 }, for: "legacy")
        registry.store({ libriVoxCalls += 1 }, for: "librivox")

        registry.take(for: "librivox")?()

        #expect(legacyCalls == 0)
        #expect(libriVoxCalls == 1)
        #expect(registry.take(for: "librivox") == nil)
        registry.take(for: "legacy")?()
        #expect(legacyCalls == 1)
    }

    @Test func releaseBeforeHandlerRegistrationConsumesHandlerExactlyOnce() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        registry.markRestorationReady(for: "librivox")
        #expect(registry.requestCompletion(for: "librivox") == nil)
        registry.store({ calls += 1 }, for: "librivox")?()
        registry.store({ calls += 1 }, for: "librivox")

        #expect(calls == 1)
    }

    @Test func finishBeforeMainActorCyclePreservesPendingRelease() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        registry.requestCompletion(for: "librivox")
        registry.beginCycle(for: "librivox")
        registry.store({ calls += 1 }, for: "librivox")
        registry.markRestorationReady(for: "librivox")?()

        #expect(calls == 1)
    }

    @Test func handlerRegisteredBeforeMainActorCycleIsNotDropped() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        registry.store({ calls += 1 }, for: "librivox")
        registry.beginCycle(for: "librivox")
        registry.markRestorationReady(for: "librivox")
        registry.requestCompletion(for: "librivox")?()

        #expect(calls == 1)
    }

    @Test func completionHandlerWaitsForRestorationBeforeRelease() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        #expect(registry.requestCompletion(for: "librivox") == nil)
        #expect(registry.store({ calls += 1 }, for: "librivox") == nil)
        #expect(calls == 0)
        registry.markRestorationReady(for: "librivox")?()
        #expect(calls == 1)
        #expect(registry.take(for: "librivox") == nil)
    }

    @Test func duplicateCompletionRegistrationRetainsEveryHandlerInTheCycle() {
        let registry = BackgroundSessionCompletionRegistry()
        var firstCalls = 0
        var secondCalls = 0

        #expect(registry.store({ firstCalls += 1 }, for: "librivox") == nil)
        #expect(registry.store({ secondCalls += 1 }, for: "librivox") == nil)
        registry.markRestorationReady(for: "librivox")
        registry.requestCompletion(for: "librivox")?()

        #expect(firstCalls == 1)
        #expect(secondCalls == 1)
        #expect(registry.take(for: "librivox") == nil)
    }

    @Test func separateBackgroundCyclesEachConsumeExactlyOneHandler() {
        let registry = BackgroundSessionCompletionRegistry()
        var firstCalls = 0
        var secondCalls = 0

        registry.beginCycle(for: "librivox")
        registry.store({ firstCalls += 1 }, for: "librivox")
        registry.markRestorationReady(for: "librivox")
        registry.requestCompletion(for: "librivox")?()
        registry.store({ firstCalls += 1 }, for: "librivox")

        registry.beginCycle(for: "librivox")
        registry.store({ secondCalls += 1 }, for: "librivox")
        registry.store({ secondCalls += 1 }, for: "librivox")
        registry.markRestorationReady(for: "librivox")
        registry.requestCompletion(for: "librivox")?()

        #expect(firstCalls == 1)
        #expect(secondCalls == 2)
        #expect(registry.take(for: "librivox") == nil)
    }

    @Test func handlerWaitsForAsyncRestorationGate() async {
        let registry = BackgroundSessionCompletionRegistry()
        let gate = RestorationGate()
        var calls = 0

        registry.beginCycle(for: "librivox")
        #expect(registry.requestCompletion(for: "librivox") == nil)
        registry.store({ calls += 1 }, for: "librivox")

        let restoration = Task { @MainActor in
            await gate.wait()
            registry.markRestorationReady(for: "librivox")?()
        }
        await Task.yield()
        #expect(calls == 0)
        gate.open()
        await restoration.value
        #expect(calls == 1)
    }

    @Test func durableFailureBeforeDrainReleaseStillReleasesExactlyOnce() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        registry.beginCycle(for: "librivox")
        registry.store({ calls += 1 }, for: "librivox")
        #expect(registry.markRestorationFailed(for: "librivox") == nil)
        #expect(calls == 0)
        registry.requestCompletion(for: "librivox")?()
        registry.markRestorationFailed(for: "librivox")?()

        #expect(calls == 1)
    }

    @Test func drainReleaseBeforeDurableFailureWaitsThenReleasesExactlyOnce() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        registry.beginCycle(for: "librivox")
        registry.requestCompletion(for: "librivox")
        registry.store({ calls += 1 }, for: "librivox")
        #expect(calls == 0)
        registry.markRestorationFailed(for: "librivox")?()
        #expect(calls == 1)
        registry.markRestorationFailed(for: "librivox")?()
        #expect(calls == 1)
    }

    @Test func handlerRegistrationBeforeReleaseStillWaitsForRelease() {
        let registry = BackgroundSessionCompletionRegistry()
        var calls = 0

        registry.markRestorationReady(for: "librivox")
        registry.store({ calls += 1 }, for: "librivox")
        #expect(calls == 0)
        registry.requestCompletion(for: "librivox")?()
        #expect(calls == 1)
        #expect(registry.requestCompletion(for: "librivox") == nil)
    }

    @Test func zeroWorkDrainReleasesOnlyAfterFinishEvents() {
        let drain = BackgroundEventDrain()
        #expect(drain.markFinishEventsSeen())
        #expect(!drain.markFinishEventsSeen())
    }

    @Test func eventDrainReleasesOnceAfterProcessingAndFinish() {
        let drain = BackgroundEventDrain()
        let token = drain.beginEvent()
        #expect(!drain.finishEvent(token))
        #expect(drain.markFinishEventsSeen())
        #expect(!drain.finishEvent(token))
    }

    @Test func unknownTaskDescriptionStillReleasesBackgroundEvents() {
        let drain = BackgroundEventDrain()
        let token = drain.beginEvent()
        #expect(!drain.markFinishEventsSeen())
        #expect(drain.finishEvent(token))
    }

    @Test func processingErrorStillReleasesBackgroundEvents() {
        let drain = BackgroundEventDrain()
        let token = drain.beginEvent()
        #expect(!drain.finishEvent(token))
        #expect(drain.markFinishEventsSeen())
    }
    @Test func lateDelegateWorkInvalidatesClaimUntilItFinishes() {
        let drain = BackgroundEventDrain()
        #expect(drain.markFinishEventsSeen())

        var releases = 0
        let lateToken = drain.beginEvent()
        #expect(!drain.deliverIfReady { releases += 1 })
        #expect(drain.finishEvent(lateToken))
        #expect(drain.deliverIfReady { releases += 1 })
        #expect(releases == 1)
    }

    @Test func repeatedFinishCallbackCannotReleaseNextGeneration() {
        let drain = BackgroundEventDrain()
        #expect(drain.markFinishEventsSeen())
        #expect(drain.deliverIfReady {})
        #expect(!drain.markFinishEventsSeen())

        let token = drain.beginEvent()
        #expect(!drain.markFinishEventsSeen())
        #expect(drain.finishEvent(token))
    }

    @Test func drainInvokesReleaseBodyAfterUnlockingForReentrantWork() {
        let drain = BackgroundEventDrain()
        #expect(drain.markFinishEventsSeen())

        var nestedToken: BackgroundEventDrain.Token?
        #expect(drain.deliverIfReady {
            nestedToken = drain.beginEvent()
        })
        #expect(nestedToken != nil)

        guard let nestedToken else { return }
        #expect(!drain.markFinishEventsSeen())
        #expect(drain.finishEvent(nestedToken))
    }
}

@MainActor
private final class RestorationGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }
}
