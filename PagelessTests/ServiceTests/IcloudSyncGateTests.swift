//
//  IcloudSyncGateTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct IcloudSyncGateTests {
    @Test func launchEvaluatorRequiresSubscriptionPreferenceAndUbiquityIdentity() {
        for plusIsActive in [false, true] {
            for desiredPreference in [false, true] {
                for hasUbiquityIdentity in [false, true] {
                    let expected = plusIsActive && desiredPreference && hasUbiquityIdentity
                    #expect(
                        IcloudSyncGate.evaluate(
                            plusIsActive: plusIsActive,
                            desiredPreference: desiredPreference,
                            hasUbiquityIdentity: hasUbiquityIdentity
                        ) == expected
                    )
                }
            }
        }
    }

    @Test func absentPlusBlocksSyncAndEachGrandfatheredEntitlementAllowsIt() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(!IcloudSyncGate.evaluate(
            plusIsActive: false,
            desiredPreference: true,
            hasUbiquityIdentity: true
        ))

        let legacyRecords = [
            PlusEntitlementRecord(
                productID: AIProductID.unlock,
                expirationDate: nil,
                revocationDate: nil
            ),
            PlusEntitlementRecord(
                productID: ICloudSyncProductID.monthly,
                expirationDate: now.addingTimeInterval(3_600),
                revocationDate: nil
            )
        ]

        for record in legacyRecords {
            let plusIsActive = PlusEntitlementStore.hasPlusEntitlement(in: [record], now: now)
            #expect(plusIsActive)
            #expect(IcloudSyncGate.evaluate(
                plusIsActive: plusIsActive,
                desiredPreference: true,
                hasUbiquityIdentity: true
            ))
        }

        let expiredLegacySubscription = PlusEntitlementRecord(
            productID: ICloudSyncProductID.monthly,
            expirationDate: now.addingTimeInterval(-1),
            revocationDate: nil
        )
        #expect(!PlusEntitlementStore.hasPlusEntitlement(
            in: [expiredLegacySubscription],
            now: now
        ))
    }

    @Test func capturedActiveStateIgnoresPreferenceMutationUntilRelaunch() {
        let defaults = UserDefaults.standard
        let originalPreference = defaults.object(forKey: IcloudSyncGate.preferenceKey)
        defer {
            if let originalPreference {
                defaults.set(originalPreference, forKey: IcloudSyncGate.preferenceKey)
            } else {
                defaults.removeObject(forKey: IcloudSyncGate.preferenceKey)
            }
        }

        let activeAtLaunch = IcloudSyncGate.isEnabled()
        defaults.set(!defaults.bool(forKey: IcloudSyncGate.preferenceKey), forKey: IcloudSyncGate.preferenceKey)

        #expect(IcloudSyncGate.isEnabled() == activeAtLaunch)
        #expect(IcloudSyncGate.isEnabled() == IcloudSyncGate.enabledAtLaunch)
    }
}
