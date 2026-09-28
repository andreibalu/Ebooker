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

/// Read-only view of the legacy iCloud Sync subscription.
/// New purchases are handled by `PlusEntitlementStore`; the legacy product remains readable
/// and restorable so existing subscribers keep their entitlement.
@MainActor
final class ICloudSubscriptionStore: ObservableObject {
    static let shared = ICloudSubscriptionStore()

    @Published private(set) var isSubscribed = false
    @Published private(set) var renewsOn: Date?
    @Published var restoreError: String?

    private init() {
        Task { await listenForTransactions() }
        Task { await refreshEntitlements() }
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
        isSubscribed = found
        renewsOn = renewal
        Self.writeLaunchEntitlementCache(
            LaunchEntitlementCache(isEntitled: found, verifiedAt: now, validUntil: renewal),
            defaults: .standard
        )
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

    /// Synchronous launch hint retained for migration from the legacy subscription cache.
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
