//
//  PlusEntitlementStore.swift
//  Pageless
//

import Combine
import Foundation
import StoreKit

nonisolated struct PlusEntitlementRecord: Equatable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
}

nonisolated struct PlusLaunchEntitlementCache: Codable, Equatable {
    let isEntitled: Bool
    let isPermanent: Bool
    let verifiedAt: Date
    let validUntil: Date?
}

/// StoreKit 2 state for the consolidated Unpaged Plus subscription.
///
/// This is a singleton because AppDelegate selects the SwiftData CloudKit database before
/// SwiftUI environment objects exist. `isSubscribedAtLaunch()` reads the last StoreKit-verified
/// cache synchronously; entitlement refreshes always come from `Transaction.currentEntitlements`.
@MainActor
final class PlusEntitlementStore: ObservableObject {
    static let shared = PlusEntitlementStore()

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isPlus = false
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var isRefreshingEntitlements = false
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var currentPlusSubscriptionProductID: String?
    @Published private(set) var currentPlusSubscriptionExpirationDate: Date?
    @Published private(set) var currentPlusSubscriptionHasIntroductoryOffer = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var loadError: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchasingProductID: String?
    @Published var purchaseError: String?
    @Published var restoreError: String?
    @Published private(set) var canMakePayments = true

    private init() {
        Task { await listenForTransactions() }
        Task {
            await refreshEntitlements()
            await loadProduct()
            canMakePayments = AppStore.canMakePayments
        }
    }

    var monthlyProduct: Product? { products[PlusProductID.monthly] }
    var yearlyProduct: Product? { products[PlusProductID.yearly] }

    var isInFreeTrial: Bool {
        guard currentPlusSubscriptionHasIntroductoryOffer,
              let expirationDate = currentPlusSubscriptionExpirationDate,
              expirationDate > .now,
              let productID = currentPlusSubscriptionProductID,
              let product = products[productID],
              product.subscription?.introductoryOffer?.paymentMode == .freeTrial else {
            return false
        }
        return true
    }

    var trialDaysRemaining: Int {
        guard isInFreeTrial, let expirationDate = currentPlusSubscriptionExpirationDate else {
            return 0
        }
        return max(1, Int(ceil(expirationDate.timeIntervalSinceNow / 86_400)))
    }

    var hasManageableSubscription: Bool {
        hasActiveSubscription
    }

    func product(for productID: String) -> Product? {
        products[productID]
    }

    /// Loads both Plus plans from StoreKit.
    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        loadError = nil

        do {
            let loadedProducts = try await Product.products(for: PlusProductID.all)
            products = Dictionary(uniqueKeysWithValues: loadedProducts.map { ($0.id, $0) })
            if loadedProducts.isEmpty {
                loadError = "Unpaged Plus plans could not be loaded."
            } else if loadedProducts.count < PlusProductID.all.count {
                loadError = "Some Unpaged Plus plans could not be loaded."
            }
        } catch {
            products = [:]
            loadError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        isRefreshingEntitlements = true
        defer {
            isRefreshingEntitlements = false
            hasLoadedEntitlements = true
        }

        let now = Date()
        var records: [PlusEntitlementRecord] = []
        var activePlusSubscription: (productID: String, expirationDate: Date, isIntroductory: Bool)?
        var activeSubscriptionExpirationDates: [Date] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            let record = PlusEntitlementRecord(
                productID: transaction.productID,
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate
            )
            records.append(record)

            guard Self.recordGrantsPlus(record, now: now),
                  let expirationDate = record.expirationDate else { continue }

            if transaction.productID == ICloudSyncProductID.monthly
                || PlusProductID.all.contains(transaction.productID) {
                activeSubscriptionExpirationDates.append(expirationDate)
            }

            guard PlusProductID.all.contains(transaction.productID) else { continue }
            if activePlusSubscription == nil
                || expirationDate > activePlusSubscription!.expirationDate {
                activePlusSubscription = (
                    transaction.productID,
                    expirationDate,
                    transaction.offer?.type == .introductory
                )
            }
        }

        let entitled = Self.hasPlusEntitlement(in: records, now: now)
        isPlus = entitled
        hasActiveSubscription = !activeSubscriptionExpirationDates.isEmpty
        currentPlusSubscriptionProductID = activePlusSubscription?.productID
        currentPlusSubscriptionExpirationDate = activePlusSubscription?.expirationDate
        currentPlusSubscriptionHasIntroductoryOffer = activePlusSubscription?.isIntroductory ?? false

        let hasPermanentLegacyUnlock = records.contains {
            $0.productID == AIProductID.unlock && $0.revocationDate == nil
        }
        Self.writeLaunchEntitlementCache(
            PlusLaunchEntitlementCache(
                isEntitled: entitled,
                isPermanent: hasPermanentLegacyUnlock,
                verifiedAt: now,
                validUntil: activeSubscriptionExpirationDates.max()
            )
        )
    }

    func purchase(productID: String) async {
        purchaseError = nil
        guard hasLoadedEntitlements, !isPlus else { return }
        guard PlusProductID.all.contains(productID), let product = products[productID] else {
            purchaseError = "This Unpaged Plus plan is not available right now."
            return
        }

        isPurchasing = true
        purchasingProductID = productID
        defer {
            isPurchasing = false
            purchasingProductID = nil
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard PlusProductID.all.contains(transaction.productID) else { return }
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified(_, let error):
                    purchaseError = error.localizedDescription
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch StoreKitError.userCancelled {
            // StoreKit reports some cancellations by throwing rather than returning
            // `.userCancelled`; cancelling is a choice, not an error to alert about.
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        restoreError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch StoreKitError.userCancelled {
            // Dismissing the App Store sign-in prompt is not a restore failure.
        } catch {
            restoreError = error.localizedDescription
        }
    }

    /// "1 week free" — the phrasing that reads correctly both on its own (plan chip) and
    /// after a verb ("Try 1 week free"). "1 week free trial" needs an article to be
    /// grammatical, which no caller can supply.
    static func freeTrialDisplay(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return "\(periodDescription(value: offer.period.value, unit: offer.period.unit)) free"
    }

    static func billingPeriodDisplay(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "billing period"
        }
        return periodDescription(value: period.value, unit: period.unit)
    }

    /// The plan's name as a chip label — "Monthly" / "Yearly" rather than the raw period
    /// ("1 month"), which reads like a quantity instead of a plan.
    static func planNameDisplay(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "Billing Period"
        }
        return planNameDisplay(value: period.value, unit: period.unit)
    }

    /// The period as it reads after "per" — "month", not "1 month".
    static func perPeriodDisplay(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "billing period"
        }
        return perPeriodDisplay(value: period.value, unit: period.unit)
    }

    /// Split out from the `Product` overloads so the copy rules are testable without a
    /// StoreKit session — `Product` cannot be constructed in a test.
    nonisolated static func planNameDisplay(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        guard value == 1 else {
            return periodDescription(value: value, unit: unit).capitalized
        }
        switch unit {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        @unknown default: return periodDescription(value: value, unit: unit).capitalized
        }
    }

    nonisolated static func perPeriodDisplay(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        guard value == 1 else {
            return periodDescription(value: value, unit: unit)
        }
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return periodDescription(value: value, unit: unit)
        }
    }

    nonisolated static func hasPlusEntitlement(
        in records: [PlusEntitlementRecord],
        now: Date = .now
    ) -> Bool {
        records.contains { recordGrantsPlus($0, now: now) }
    }

    nonisolated static func recordGrantsPlus(
        _ record: PlusEntitlementRecord,
        now: Date = .now
    ) -> Bool {
        guard record.revocationDate == nil else { return false }

        if record.productID == AIProductID.unlock {
            return true
        }

        let isSubscription = record.productID == ICloudSyncProductID.monthly
            || PlusProductID.all.contains(record.productID)
        guard isSubscription,
              let expirationDate = record.expirationDate else { return false }
        return expirationDate > now
    }

    /// Synchronous launch hint used by AppDelegate before StoreKit's async APIs are available.
    nonisolated static func isSubscribedAtLaunch(
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let data = defaults.data(forKey: launchEntitlementCacheKey),
           let cache = try? JSONDecoder().decode(PlusLaunchEntitlementCache.self, from: data) {
            guard cache.isEntitled else { return false }
            if cache.isPermanent { return true }
            guard let validUntil = cache.validUntil else { return false }
            return validUntil > now
        }

        // Preserve the old verified iCloud launch cache until Plus writes its own cache. This
        // prevents an existing subscriber's first launch after upgrade from selecting a local
        // SwiftData store before the asynchronous entitlement refresh completes.
        return ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: defaults)
    }

    nonisolated static func writeLaunchEntitlementCache(
        _ cache: PlusLaunchEntitlementCache,
        defaults: UserDefaults = .standard
    ) {
        do {
            defaults.set(try JSONEncoder().encode(cache), forKey: launchEntitlementCacheKey)
        } catch {
            assertionFailure("Could not encode Unpaged Plus launch entitlement cache")
        }
    }

    nonisolated private static let launchEntitlementCacheKey = "unpagedPlusLaunchEntitlement"

    nonisolated static func periodDescription(
        value: Int,
        unit: Product.SubscriptionPeriod.Unit
    ) -> String {
        let unitName: String
        switch unit {
        case .day: unitName = value == 1 ? "day" : "days"
        case .week: unitName = value == 1 ? "week" : "weeks"
        case .month: unitName = value == 1 ? "month" : "months"
        case .year: unitName = value == 1 ? "year" : "years"
        @unknown default: unitName = "periods"
        }
        return "\(value) \(unitName)"
    }

    private static func handlesTransaction(productID: String) -> Bool {
        PlusProductID.all.contains(productID)
            || productID == AIProductID.unlock
            || productID == ICloudSyncProductID.monthly
    }

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            switch verification {
            case .verified(let transaction):
                guard Self.handlesTransaction(productID: transaction.productID) else { continue }
                await transaction.finish()
                await refreshEntitlements()
            case .unverified:
                break
            }
        }
    }
}
