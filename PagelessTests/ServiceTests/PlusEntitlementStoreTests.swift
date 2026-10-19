//
//  PlusEntitlementStoreTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct PlusEntitlementStoreTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    /// Wall-clock trial lengths across a DST change must not gain or lose a day, which an
    /// interval / 86,400 count does (7 days spanning the fall-back is 169 hours).
    @Test(arguments: [
        ("Europe/Bucharest", 2026, 10, 22),
        ("America/New_York", 2026, 11, 1),
        ("Europe/Bucharest", 2026, 3, 27),
        ("Pacific/Auckland", 2026, 9, 25),
        ("UTC", 2026, 6, 1)
    ])
    func trialDaysRemainingIgnoresDaylightSavingChanges(zone: String, year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let start = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 15, minute: 30)))
        for hour in [0, 15, 23] {
            let expiry = try #require(calendar.date(byAdding: .day, value: 7, to: start))
            let late = try #require(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: expiry))
            #expect(PlusEntitlementStore.calendarDaysRemaining(until: late, now: start, calendar: calendar) == 7)
        }
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(PlusEntitlementStore.calendarDaysRemaining(until: nextDay, now: start, calendar: calendar) == 1)
        #expect(PlusEntitlementStore.calendarDaysRemaining(until: start.addingTimeInterval(60), now: start, calendar: calendar) == 1)
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
