//
//  ICloudSubscriptionStore.swift
//  Pageless
//

import Combine
import Foundation
import RevenueCat
import StoreKit

/// StoreKit 2 state for the auto-renewable iCloud Sync subscription.
///
/// A singleton (`shared`) is required because `AppDelegate.init` reads subscription state
/// when building the SwiftData container at process launch — before SwiftUI environment
/// objects exist. The same instance is also injected as an `@EnvironmentObject` so views
/// can observe published state.
@MainActor
final class ICloudSubscriptionStore: ObservableObject {
    static let shared = ICloudSubscriptionStore()

    @Published private(set) var product: Product?
    @Published private(set) var isSubscribed = false
    @Published private(set) var renewsOn: Date?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var loadError: String?
    @Published private(set) var isPurchasing = false
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

    /// Shown in settings when StoreKit price is not loaded yet.
    var unlockPriceDisplay: String {
        product?.displayPrice ?? "$0.99"
    }

    var trialPeriodDisplay: String {
        guard let intro = product?.subscription?.introductoryOffer else {
            return "7-day free trial"
        }
        let value = intro.period.value
        switch intro.period.unit {
        case .day: return "\(value)-day free trial"
        case .week: return value == 1 ? "7-day free trial" : "\(value)-week free trial"
        case .month: return "\(value)-month free trial"
        case .year: return "\(value)-year free trial"
        @unknown default: return "Free trial"
        }
    }

    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        loadError = nil
        do {
            let products = try await Product.products(for: [ICloudSyncProductID.monthly])
            product = products.first
            if product == nil {
                loadError = "Could not load product from the App Store."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var found = false
        var renewal: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == ICloudSyncProductID.monthly else { continue }
            if transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                found = true
                renewal = transaction.expirationDate
                break
            }
        }
        if isSubscribed != found {
            isSubscribed = found
        }
        if renewsOn != renewal {
            renewsOn = renewal
        }
        UserDefaults.standard.set(found, forKey: Self.subscribedCacheKey)
    }

    func purchase() async {
        purchaseError = nil
        guard let product else {
            purchaseError = "Product is not available yet."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if Purchases.isConfigured {
                _ = try? await Purchases.shared.recordPurchase(result)
            }
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard transaction.productID == ICloudSyncProductID.monthly else { return }
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
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        restoreError = nil
        do {
            try await AppStore.sync()
            if Purchases.isConfigured {
                _ = try? await Purchases.shared.syncPurchases()
            }
            await refreshEntitlements()
        } catch {
            restoreError = error.localizedDescription
        }
    }

    /// Synchronous snapshot used by `IcloudSyncGate.isEnabled()` at app launch
    /// (before any async refresh has run). Reads the UserDefaults cache written by
    /// the most recent `refreshEntitlements()` — the user keeps sync access across
    /// the brief window between launch and the first async refresh.
    nonisolated static func isSubscribedAtLaunch() -> Bool {
        UserDefaults.standard.bool(forKey: subscribedCacheKey)
    }

    fileprivate static let subscribedCacheKey = "iCloudSyncSubscribed"

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            switch verification {
            case .verified(let transaction):
                guard transaction.productID == ICloudSyncProductID.monthly else { continue }
                await transaction.finish()
                if Purchases.isConfigured {
                    _ = try? await Purchases.shared.syncPurchases()
                }
                await refreshEntitlements()
            case .unverified:
                break
            }
        }
    }
}

