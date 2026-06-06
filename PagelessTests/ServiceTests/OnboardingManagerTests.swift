//
//  OnboardingManagerTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct OnboardingManagerTests {

    private func isolatedDefaults() -> UserDefaults {
        let suite = "test.onboarding.\(UUID().uuidString)"
        guard let ud = UserDefaults(suiteName: suite) else {
            fatalError("Could not create UserDefaults suite")
        }
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    @Test func freshInstallShowsOnboarding() {
        let ud = isolatedDefaults()
        let m = OnboardingManager(defaults: ud)
        #expect(m.isComplete == false)
    }

    @Test func completePersistsAcrossRelaunch() {
        let ud = isolatedDefaults()

        let first = OnboardingManager(defaults: ud)
        first.complete()
        #expect(first.isComplete == true)

        // A new manager reading the same defaults should stay complete.
        let relaunched = OnboardingManager(defaults: ud)
        #expect(relaunched.isComplete == true)
    }

    @Test func resetReshowsOnboarding() {
        let ud = isolatedDefaults()
        let m = OnboardingManager(defaults: ud)
        m.complete()
        m.reset()
        #expect(m.isComplete == false)

        let relaunched = OnboardingManager(defaults: ud)
        #expect(relaunched.isComplete == false)
    }

    @Test func legacyCompletedWalkthroughCountsAsComplete() {
        // Users who finished the old spotlight walkthrough (legacy phase == 3) must not be
        // shown the new onboarding again.
        let ud = isolatedDefaults()
        ud.set(3, forKey: "onboardingPhase")

        let m = OnboardingManager(defaults: ud)
        #expect(m.isComplete == true)
    }

    @Test func legacyUnfinishedWalkthroughStillShowsOnboarding() {
        // A user mid-walkthrough (legacy phase != 3) sees the new onboarding.
        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        ud.set(2, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        #expect(m.isComplete == false)
    }

    @Test func explicitFlagWinsOverLegacyPhase() {
        // Once the new flag is written it is authoritative, regardless of any legacy phase value.
        let ud = isolatedDefaults()
        ud.set(3, forKey: "onboardingPhase")
        ud.set(false, forKey: "onboardingComplete")

        let m = OnboardingManager(defaults: ud)
        #expect(m.isComplete == false)
    }
}
