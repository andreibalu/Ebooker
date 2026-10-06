//
//  StoreKitTransactionTests.swift
//  PagelessTests
//
//  Real StoreKit 2 transaction flows against the local `Products.storekit` configuration.
//  `SKTestSession` only reaches the process it runs in, so these tests are app-hosted and drive
//  the production stores directly; `xcodebuild test` does not apply a scheme's StoreKit file to
//  UI-test launches. Pricing, review metadata and sandbox receipts remain a TestFlight concern.
//
//  Failure and cancellation are deliberately absent. A simulated purchase failure makes storekitd
//  present a blocking "Unable to Complete Purchase" system alert that `disableDialogs` does not
//  suppress, and a simulated `.userCancelled` reaches the app as a generic "Unable to Complete
//  Request" error rather than a cancellation. Both run in e2e/tests/purchases.e2e.ts against the
//  real payment sheet instead.
//
//  The session is reset in `init` only: a `deinit` reset is not awaited and can overlap the next
//  test's purchase, which leaves transactions unfinishable.
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Pageless

@MainActor
@Suite(.serialized)
final class StoreKitTransactionTests {
    private let session: SKTestSession

    init() throws {
        // App-hosted simulator tests can read the repository, so the scheme's configuration is
        // the single source of truth instead of a copy that could drift.
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Pageless/Configuration/Products.storekit")
        session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
    }

    private func freshPlusStore() async -> PlusEntitlementStore {
        let store = PlusEntitlementStore.shared
        store.purchaseError = nil
        store.restoreError = nil
        await store.refreshEntitlements()
        await store.loadProduct()
        return store
    }

    // MARK: - Unpaged Plus

    @Test func plusPlansLoadWithTheirTrialAndPlanNames() async throws {
        let store = await freshPlusStore()
        let monthly = try #require(store.monthlyProduct)
        let yearly = try #require(store.yearlyProduct)

        #expect(store.loadError == nil)
        #expect(PlusEntitlementStore.planNameDisplay(for: monthly) == "Monthly")
        #expect(PlusEntitlementStore.planNameDisplay(for: yearly) == "Yearly")
        #expect(PlusEntitlementStore.freeTrialDisplay(for: monthly) == "1 week free")
        #expect(PlusEntitlementStore.freeTrialDisplay(for: yearly) == "1 week free")
        #expect(store.isPlus == false)
    }

    @Test func monthlyPurchaseStartsTheTrialAndWritesTheLaunchCache() async throws {
        let store = await freshPlusStore()

        await store.purchase(productID: PlusProductID.monthly)

        #expect(store.purchaseError == nil)
        #expect(store.isPlus)
        #expect(store.isInFreeTrial)
        #expect(store.trialDaysRemaining == 7)
        #expect(store.hasManageableSubscription)
        #expect(store.currentPlusSubscriptionProductID == PlusProductID.monthly)
        #expect(PlusEntitlementStore.isSubscribedAtLaunch())
        let finished = await Self.waitUntil { await Self.unfinishedTransactionCount() == 0 }
        let ledger = await Self.describeLedger(session)
        #expect(finished, "A delivered Plus purchase must be finished: \(ledger)")
    }

    @Test func yearlyPurchaseRecordsTheYearlyPlan() async throws {
        let store = await freshPlusStore()

        await store.purchase(productID: PlusProductID.yearly)

        #expect(store.isPlus)
        #expect(store.currentPlusSubscriptionProductID == PlusProductID.yearly)
        #expect(session.allTransactions().map(\.productIdentifier) == [PlusProductID.yearly])
    }

    @Test func askToBuyStaysLockedUntilApprovedThenUnlocksThroughUpdates() async throws {
        session.askToBuyEnabled = true
        let store = await freshPlusStore()

        await store.purchase(productID: PlusProductID.monthly)
        #expect(store.purchaseError == "Purchase is pending approval.")
        #expect(store.isPlus == false)

        let pending = try #require(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        // No call into the store: only the app's Transaction.updates listener can unlock it.
        #expect(await Self.waitUntil { store.isPlus }, "An approved Ask to Buy must unlock Plus")
    }

    @Test func expiredSubscriptionStopsGrantingPlus() async throws {
        let store = await freshPlusStore()
        await store.purchase(productID: PlusProductID.monthly)
        #expect(store.isPlus)

        try session.expireSubscription(productIdentifier: PlusProductID.monthly)
        // The session ledger changes at once; the app's entitlement cache catches up shortly after.
        _ = await Self.waitUntil {
            await store.refreshEntitlements()
            return !store.isPlus
        }

        let ledger = await Self.describeLedger(session)
        #expect(store.isPlus == false, "\(ledger)")
        #expect(store.hasManageableSubscription == false)
        #expect(PlusEntitlementStore.isSubscribedAtLaunch() == false)
    }

    @Test func refundedSubscriptionIsRevoked() async throws {
        let store = await freshPlusStore()
        await store.purchase(productID: PlusProductID.monthly)
        let purchase = try #require(session.allTransactions().first)

        try session.refundTransaction(identifier: purchase.identifier)
        _ = await Self.waitUntil {
            await store.refreshEntitlements()
            return !store.isPlus
        }

        #expect(store.isPlus == false)
    }

    @Test func restoreKeepsAnExistingSubscriptionWithoutError() async throws {
        try await session.buyProduct(identifier: PlusProductID.monthly)
        let store = await freshPlusStore()

        await store.restorePurchases()

        #expect(store.restoreError == nil)
        #expect(store.isPlus)
    }

    @Test func restoreWithNothingToRestoreLeavesTheOfferWithoutError() async throws {
        let store = await freshPlusStore()

        await store.restorePurchases()

        #expect(store.restoreError == nil)
        #expect(store.isPlus == false)
    }

    @Test func legacyAIUnlockStillGrantsPlusPermanently() async throws {
        try await session.buyProduct(identifier: AIProductID.unlock)
        let store = await freshPlusStore()

        let ledger = await Self.describeLedger(session)
        #expect(store.isPlus, "\(ledger)")
        #expect(store.hasManageableSubscription == false, "A one-time unlock has nothing to manage")
        #expect(PlusEntitlementStore.isSubscribedAtLaunch())
    }

    @Test func legacyICloudSubscriptionStillGrantsPlus() async throws {
        try await session.buyProduct(identifier: ICloudSyncProductID.monthly)
        let store = await freshPlusStore()

        #expect(store.isPlus)
        #expect(store.hasManageableSubscription)
    }

    @Test func activePlusMakesFurtherPurchasesANoOp() async throws {
        let store = await freshPlusStore()
        await store.purchase(productID: PlusProductID.monthly)

        await store.purchase(productID: PlusProductID.yearly)

        #expect(session.allTransactions().count == 1, "Plus must not be bought twice")
    }

    // MARK: - Coffee tip

    private func loadedCoffeeStore() async throws -> CoffeeTipStore {
        let store = CoffeeTipStore()
        #expect(await Self.waitUntil { store.product != nil }, "The coffee product must load")
        return store
    }

    @Test func coffeeTipSucceedsRepeatsAndFinishesEachTransaction() async throws {
        let store = try await loadedCoffeeStore()
        #expect(store.purchaseButtonTitle == "Buy a coffee \u{2014} $2.99")

        await store.purchase()
        #expect(store.purchaseState == .succeeded)
        // A consumable can be bought again only once the previous one is finished.
        #expect(await Self.waitUntil { await Self.unfinishedTransactionCount() == 0 })
        await store.purchase()
        #expect(store.purchaseState == .succeeded)

        let coffees = session.allTransactions().filter { $0.productIdentifier == CoffeeTipProductID.coffee }
        #expect(coffees.count == 2, "A consumable tip must be repeatable")
        #expect(await Self.waitUntil { await Self.unfinishedTransactionCount() == 0 })

        let plus = await freshPlusStore()
        #expect(plus.isPlus == false, "A tip must never unlock features")
    }

    @Test func coffeeTipPendingApprovalThanksOnlyAfterApproval() async throws {
        session.askToBuyEnabled = true
        let store = try await loadedCoffeeStore()

        await store.purchase()
        #expect(store.purchaseState == .pending)

        let pending = try #require(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        #expect(await Self.waitUntil { store.purchaseState == .succeeded })
        #expect(await Self.waitUntil { await Self.unfinishedTransactionCount() == 0 })
    }

    @Test func coffeeTipBoughtOutsideTheButtonIsFinishedAndThanked() async throws {
        // Covers a purchase completed elsewhere (another device, an interrupted launch): it
        // arrives only through the store's transaction streams.
        let store = try await loadedCoffeeStore()

        try await session.buyProduct(identifier: CoffeeTipProductID.coffee)

        #expect(await Self.waitUntil { store.purchaseState == .succeeded })
        #expect(await Self.waitUntil { await Self.unfinishedTransactionCount() == 0 })
    }

    // MARK: - Helpers

    private static func describeLedger(_ session: SKTestSession) async -> String {
        let all = session.allTransactions().map { "\($0.productIdentifier) state=\($0.state.rawValue) finished? exp=\(String(describing: $0.expirationDate))" }
        var current: [String] = []
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let t): current.append("verified \(t.productID) exp=\(String(describing: t.expirationDate)) rev=\(String(describing: t.revocationDate))")
            case .unverified(let t, let e): current.append("UNVERIFIED \(t.productID) \(e)")
            }
        }
        var unfinished: [String] = []
        for await result in Transaction.unfinished { unfinished.append("\(result.unsafePayloadValue.productID)") }
        return "session=\(all) current=\(current) unfinished=\(unfinished)"
    }

    private static func unfinishedTransactionCount() async -> Int {
        var count = 0
        for await _ in Transaction.unfinished { count += 1 }
        return count
    }

    private static func waitUntil(
        timeout: Duration = .seconds(15),
        _ condition: @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return await condition()
    }
}
