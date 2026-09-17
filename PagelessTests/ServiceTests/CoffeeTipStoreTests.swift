//
//  CoffeeTipStoreTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

@MainActor
struct CoffeeTipStoreTests {
    @Test func productIDIsTheSingleConsumableCoffeeProduct() {
        #expect(CoffeeTipProductID.coffee == "andreibaludev.Pageless.tip.coffee")
    }

    @Test func noPriceFallbackIsShownBeforeStoreKitLoadsAProduct() {
        let store = CoffeeTipStore(startTasks: false)

        #expect(store.product == nil)
        #expect(store.coffeePriceDisplay == nil)
        #expect(store.purchaseButtonTitle == "Buy a coffee")
    }

    @Test(arguments: [
        CoffeeTipPurchaseResolution.userCancelled,
        CoffeeTipPurchaseResolution.pending,
        CoffeeTipPurchaseResolution.unavailable,
        CoffeeTipPurchaseResolution.unverified,
        CoffeeTipPurchaseResolution.failed,
    ])
    func nonVerifiedOutcomesNeverShowThanks(_ resolution: CoffeeTipPurchaseResolution) {
        #expect(CoffeeTipStore.state(for: resolution) != .succeeded)
    }

    @Test func verifiedOutcomeShowsThanksForThisPurchase() {
        #expect(CoffeeTipStore.state(for: .verified) == .succeeded)
    }

    @Test func cancelledPurchaseLeavesStoreReadyForAnotherAttempt() async {
        let store = CoffeeTipStore(
            purchaseOutcomeProvider: { .userCancelled },
            startTasks: false
        )

        await store.purchase()

        #expect(store.purchaseState == .cancelled)
        #expect(store.isPurchasing == false)
    }

    @Test func pendingPurchaseDoesNotShowThanksBeforeApproval() async {
        let store = CoffeeTipStore(
            purchaseOutcomeProvider: { .pending },
            startTasks: false
        )

        await store.purchase()

        #expect(store.purchaseState == .pending)
        #expect(store.purchaseState != .succeeded)
    }

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
