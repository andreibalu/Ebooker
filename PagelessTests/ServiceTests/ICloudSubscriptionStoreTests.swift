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

    @Test func untrustworthyCachesFailClosed() {
        let now = Date(timeIntervalSince1970: 1_000)

        let falseCache = isolatedDefaults()
        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            cache(entitled: false, verifiedAt: now, validUntil: now.addingTimeInterval(86_400)),
            defaults: falseCache
        )
        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: falseCache))

        let trueWithoutExpiration = isolatedDefaults()
        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            cache(entitled: true, verifiedAt: now, validUntil: nil),
            defaults: trueWithoutExpiration
        )
        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: trueWithoutExpiration))

        let malformed = isolatedDefaults()
        malformed.set(Data("not-json".utf8), forKey: cacheKey)
        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: malformed))

        let legacyFalse = isolatedDefaults()
        legacyFalse.set(false, forKey: legacySubscribedKey)
        #expect(!ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: legacyFalse))
    }

    @Test func futureExpirationAuthorizesLaunch() {
        let defaults = isolatedDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            cache(entitled: true, verifiedAt: now, validUntil: now.addingTimeInterval(1)),
            defaults: defaults
        )

        #expect(ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: defaults))
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

    @Test func verifiedWriteRemovesLegacyKeysAfterWritingEncodedRecord() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: legacySubscribedKey)
        defaults.set(Date(timeIntervalSince1970: 1_000), forKey: legacyFirstSeenKey)
        let now = Date(timeIntervalSince1970: 1_000)

        ICloudSubscriptionStore.writeLaunchEntitlementCache(
            cache(entitled: true, verifiedAt: now, validUntil: now.addingTimeInterval(86_400)),
            defaults: defaults
        )

        #expect(defaults.data(forKey: cacheKey) != nil)
        #expect(defaults.object(forKey: legacySubscribedKey) == nil)
        #expect(defaults.object(forKey: legacyFirstSeenKey) == nil)
    }

    @Test func readerNeverCombinesLegacyBooleanWithSeparateExpirationKey() {
        let defaults = isolatedDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        defaults.set(true, forKey: legacySubscribedKey)
        defaults.set(now.addingTimeInterval(-1), forKey: "iCloudSyncSubscriptionExpiration")

        #expect(ICloudSubscriptionStore.isSubscribedAtLaunch(now: now, defaults: defaults))
    }
}
