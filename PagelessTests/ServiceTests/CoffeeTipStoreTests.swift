//
//  CoffeeTipStoreTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

@MainActor
struct CoffeeTipStoreTests {
    @Test func purchasesAreSerializedAndASecondTipRemainsAvailable() async {
        let probe = CoffeeTipPurchaseProbe()
        let store = CoffeeTipStore(
            purchaseOutcomeProvider: { await probe.outcome() },
            startTasks: false
        )

        let firstPurchase = Task { @MainActor in
            await store.purchase()
        }
        await probe.waitForFirstCall()

        await store.purchase()

        #expect(await probe.callCount() == 1)
        #expect(store.isPurchasing)

        await probe.releaseFirst()
        await firstPurchase.value

        #expect(await probe.callCount() == 1)
        #expect(store.purchaseState == .succeeded)
        #expect(store.isPurchasing == false)

        await store.purchase()

        #expect(store.purchaseState == .succeeded)
        #expect(store.isPurchasing == false)
        #expect(await probe.callCount() == 2)
    }
}

private actor CoffeeTipPurchaseProbe {
    private var calls = 0
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var firstReleaseContinuation: CheckedContinuation<CoffeeTipPurchaseResolution, Never>?

    func outcome() async -> CoffeeTipPurchaseResolution {
        calls += 1
        guard calls == 1 else { return .verified }

        firstCallContinuation?.resume()
        firstCallContinuation = nil
        return await withCheckedContinuation { continuation in
            firstReleaseContinuation = continuation
        }
    }

    func waitForFirstCall() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { continuation in
            firstCallContinuation = continuation
        }
    }

    func releaseFirst() {
        firstReleaseContinuation?.resume(returning: .verified)
        firstReleaseContinuation = nil
    }

    func callCount() -> Int {
        calls
    }
}
