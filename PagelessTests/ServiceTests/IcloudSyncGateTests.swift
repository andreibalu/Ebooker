//
//  IcloudSyncGateTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct IcloudSyncGateTests {
    @Test func launchEvaluatorRequiresSubscriptionPreferenceAndUbiquityIdentity() {
        for subscriptionIsActive in [false, true] {
            for desiredPreference in [false, true] {
                for hasUbiquityIdentity in [false, true] {
                    let expected = subscriptionIsActive && desiredPreference && hasUbiquityIdentity
                    #expect(
                        IcloudSyncGate.evaluate(
                            subscriptionIsActive: subscriptionIsActive,
                            desiredPreference: desiredPreference,
                            hasUbiquityIdentity: hasUbiquityIdentity
                        ) == expected
                    )
                }
            }
        }
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
