//
//  ICloudSubscriptionStoreTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct ICloudSubscriptionStoreTests {
    private let cacheKey = "iCloudSyncLaunchEntitlement"
    private let legacySubscribedKey = "iCloudSyncSubscribed"
    private let legacyFirstSeenKey = "iCloudSyncLegacyCacheFirstSeenAt"

    private func isolatedDefaults() -> UserDefaults {
        let suite = "test.icloud.subscription.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func cache(
        entitled: Bool,
        verifiedAt: Date,
        validUntil: Date?
    ) -> LaunchEntitlementCache {
        LaunchEntitlementCache(
            isEntitled: entitled,
            verifiedAt: verifiedAt,
            validUntil: validUntil
        )
    }

    @Test(arguments: [
        1_000.0,
        1_001.0,
    ])
    func equalOrPastExpirationNeverAuthorizesLaunch(nowTimestamp: TimeInterval) {
        let defaults = isolatedDefaults()
        let now = Date(timeIntervalSince1970: nowTimestamp)
        let expiration = Date(timeIntervalSince1970: 1_000)
        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            cache(entitled: true, verifiedAt: Date(timeIntervalSince1970: 0), validUntil: expiration),
            defaults: defaults
        )

        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: defaults))
    }

    @Test func encodedTrueWithoutExpirationFailsClosed() {
        let defaults = isolatedDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            cache(entitled: true, verifiedAt: now, validUntil: nil),
            defaults: defaults
        )

        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: defaults))
    }

    @Test func malformedCacheFailsClosed() {
        let defaults = isolatedDefaults()
        defaults.set(Data("not-json".utf8), forKey: cacheKey)

        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(
            now: Date(timeIntervalSince1970: 1_000),
            defaults: defaults
        ))
    }

    @Test func legacyTrueAuthorizesOnlyFromFirstReadForTwentyFourHours() {
        let defaults = isolatedDefaults()
        let firstRead = Date(timeIntervalSince1970: 1_000)
        defaults.set(true, forKey: legacySubscribedKey)

        #expect(ICloudSubscriptionStore.isSubscribedAtLaunch(now: firstRead, defaults: defaults))
        #expect(ICloudSubscriptionStore.isSubscribedAtLaunch(
            now: firstRead.addingTimeInterval(86_399), defaults: defaults
        ))
        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(
            now: firstRead.addingTimeInterval(86_400), defaults: defaults
        ))
        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(
            now: firstRead.addingTimeInterval(86_401), defaults: defaults
        ))

        #expect(defaults.object(forKey: legacyFirstSeenKey) as? Date == firstRead)
    }

}
