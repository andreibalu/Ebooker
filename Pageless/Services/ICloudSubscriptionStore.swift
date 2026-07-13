//
//  ICloudSubscriptionStore.swift
//  Pageless
//

import Combine
import Foundation
import StoreKit

nonisolated struct LaunchEntitlementCache: Codable, Equatable {
    let isEntitled: Bool
    let verifiedAt: Date
    let validUntil: Date?
}

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

    /// Non-nil only when the App Store product actually carries a free-trial introductory
    /// offer. Returns nil otherwise so the UI never promises a trial that doesn't exist.
    var introOfferDisplay: String? {
        guard let intro = product?.subscription?.introductoryOffer,
              intro.paymentMode == .freeTrial else { return nil }
        let value = intro.period.value
        switch intro.period.unit {
        case .day: return value == 7 ? "7-day free trial" : "\(value)-day free trial"
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
        let now = Date()
        var found = false
        var renewal: Date?
        var missingExpiration = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == ICloudSyncProductID.monthly else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard let expirationDate = transaction.expirationDate else {
                missingExpiration = true
                break
            }
            if expirationDate > now {
                found = true
                renewal = expirationDate
                break
            }
        }
        if missingExpiration {
            assertionFailure("iCloud Sync entitlement has no expiration date")
            found = false
            renewal = nil
        }
        if isSubscribed != found {
            isSubscribed = found
        }
        if renewsOn != renewal {
            renewsOn = renewal
        }
        Self.writeLaunchEntitlementCache(
            LaunchEntitlementCache(isEntitled: found, verifiedAt: now, validUntil: renewal),
            defaults: .standard
        )
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
            await refreshEntitlements()
        } catch {
            restoreError = error.localizedDescription
        }
    }

    /// Synchronous launch hint used before StoreKit's async entitlement APIs are available.
    /// Encoded entitlements require a future expiration. Legacy Boolean-only installs receive
    /// a bounded migration window so they do not retain indefinite access.
    nonisolated static func isSubscribedAtLaunch(
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let data = defaults.data(forKey: launchEntitlementCacheKey),
           let cache = try? JSONDecoder().decode(LaunchEntitlementCache.self, from: data) {
            guard cache.isEntitled else { return false }
            guard let validUntil = cache.validUntil, validUntil > now else { return false }
            return true
        }

        guard defaults.bool(forKey: subscribedCacheKey) else { return false }
        let firstSeenAt: Date
        if let stored = defaults.object(forKey: legacyCacheFirstSeenAtKey) as? Date {
            firstSeenAt = stored
        } else {
            firstSeenAt = now
            defaults.set(firstSeenAt, forKey: legacyCacheFirstSeenAtKey)
        }
        return now < firstSeenAt.addingTimeInterval(legacyMigrationWindow)
    }

    nonisolated static func writeLaunchEntitlementCache(
        _ cache: LaunchEntitlementCache,
        defaults: UserDefaults = .standard
    ) {
        do {
            let data = try JSONEncoder().encode(cache)
            defaults.set(data, forKey: launchEntitlementCacheKey)
            defaults.removeObject(forKey: subscribedCacheKey)
            defaults.removeObject(forKey: legacyCacheFirstSeenAtKey)
        } catch {
            assertionFailure("Could not encode iCloud Sync launch entitlement cache")
        }
    }

    nonisolated private static let launchEntitlementCacheKey = "iCloudSyncLaunchEntitlement"
    nonisolated fileprivate static let subscribedCacheKey = "iCloudSyncSubscribed"
    nonisolated private static let legacyCacheFirstSeenAtKey = "iCloudSyncLegacyCacheFirstSeenAt"
    nonisolated private static let legacyMigrationWindow: TimeInterval = 86_400

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            switch verification {
            case .verified(let transaction):
                guard transaction.productID == ICloudSyncProductID.monthly else { continue }
                await transaction.finish()
                await refreshEntitlements()
            case .unverified:
                break
            }
        }
    }
}
