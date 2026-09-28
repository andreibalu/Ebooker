//
//  PlusEntitlementStoreTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct PlusEntitlementStoreTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test(arguments: [PlusProductID.monthly, PlusProductID.yearly])
    func activePlusPlansGrantEntitlement(productID: String) {
        let record = PlusEntitlementRecord(
            productID: productID,
            expirationDate: now.addingTimeInterval(86_400),
            revocationDate: nil
        )

        #expect(PlusEntitlementStore.hasPlusEntitlement(in: [record], now: now))
    }

    @Test func legacyAIPurchaseIndependentlyGrantsEntitlement() {
        let legacyAIUnlock = PlusEntitlementRecord(
            productID: AIProductID.unlock,
            expirationDate: nil,
            revocationDate: nil
        )

        #expect(PlusEntitlementStore.hasPlusEntitlement(in: [legacyAIUnlock], now: now))
    }

    @Test func activeLegacyICloudSubscriptionIndependentlyGrantsEntitlement() {
        let legacyICloudSubscription = PlusEntitlementRecord(
            productID: ICloudSyncProductID.monthly,
            expirationDate: now.addingTimeInterval(86_400),
            revocationDate: nil
        )

        #expect(PlusEntitlementStore.hasPlusEntitlement(in: [legacyICloudSubscription], now: now))
    }

    @Test func noRecognizedEntitlementReturnsFalse() {
        let records = [
            PlusEntitlementRecord(
                productID: "andreibaludev.Pageless.tip.coffee",
                expirationDate: nil,
                revocationDate: nil
            ),
            PlusEntitlementRecord(
                productID: "unknown.product",
                expirationDate: now.addingTimeInterval(86_400),
                revocationDate: nil
            )
        ]

        #expect(!PlusEntitlementStore.hasPlusEntitlement(in: records, now: now))
    }

    @Test func expiredLegacyICloudDoesNotEntitleButOwnedAIUnlockStillDoes() {
        let expiredICloudSubscription = PlusEntitlementRecord(
            productID: ICloudSyncProductID.monthly,
            expirationDate: now.addingTimeInterval(-1),
            revocationDate: nil
        )
        let ownedAIUnlock = PlusEntitlementRecord(
            productID: AIProductID.unlock,
            expirationDate: nil,
            revocationDate: nil
        )

        #expect(!PlusEntitlementStore.hasPlusEntitlement(
            in: [expiredICloudSubscription],
            now: now
        ))
        #expect(PlusEntitlementStore.hasPlusEntitlement(
            in: [expiredICloudSubscription, ownedAIUnlock],
            now: now
        ))
    }

    @Test func revokedLegacyAIPurchaseDoesNotEntitle() {
        let revokedAIUnlock = PlusEntitlementRecord(
            productID: AIProductID.unlock,
            expirationDate: nil,
            revocationDate: now.addingTimeInterval(-100)
        )

        #expect(!PlusEntitlementStore.hasPlusEntitlement(in: [revokedAIUnlock], now: now))
    }

    @Test func launchCacheKeepsPermanentLegacyUnlockAndExpiresSubscriptions() {
        let suite = "test.unpaged.plus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PlusEntitlementStore.writeLaunchEntitlementCache(
            PlusLaunchEntitlementCache(
                isEntitled: true,
                isPermanent: true,
                verifiedAt: now,
                validUntil: nil
            ),
            defaults: defaults
        )
        #expect(PlusEntitlementStore.isSubscribedAtLaunch(
            now: now.addingTimeInterval(10 * 365 * 86_400),
            defaults: defaults
        ))

        PlusEntitlementStore.writeLaunchEntitlementCache(
            PlusLaunchEntitlementCache(
                isEntitled: true,
                isPermanent: false,
                verifiedAt: now,
                validUntil: now.addingTimeInterval(1)
            ),
            defaults: defaults
        )
        #expect(!PlusEntitlementStore.isSubscribedAtLaunch(
            now: now.addingTimeInterval(2),
            defaults: defaults
        ))
    }

    @Test func launchFallsBackToThePreviouslyVerifiedLegacyICloudCache() {
        let suite = "test.unpaged.plus.legacy-cache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            LaunchEntitlementCache(
                isEntitled: true,
                verifiedAt: now,
                validUntil: now.addingTimeInterval(86_400)
            ),
            defaults: defaults
        )

        #expect(PlusEntitlementStore.isSubscribedAtLaunch(now: now, defaults: defaults))
    }
}
