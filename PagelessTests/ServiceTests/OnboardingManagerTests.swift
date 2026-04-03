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

    @Test func aiCapablePhase1AdvanceMatchesOriginalFlow() {
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = true
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        let m = OnboardingManager(defaults: ud)

        #expect(m.currentStep == .p1AddButton)
        #expect(m.totalStepsInPhase == 4)

        m.advance()
        #expect(m.currentStep == .p1Settings)
        #expect(m.requestOpenSettings == false)

        m.advance()
        #expect(m.currentStep == .p1AILink)
        #expect(m.requestOpenSettings == true)
        m.requestOpenSettings = false

        m.advance()
        #expect(m.currentStep == .p1AIPage)
        #expect(m.requestNavigateToAISettings == true)
        m.requestNavigateToAISettings = false

        m.advance()
        #expect(m.currentStep == nil)
        #expect(m.phaseRaw == 1) // waitingForBook
        #expect(m.stepIndex == 0)
        #expect(m.requestDismissSettings == true)
    }

    @Test func nonAIPhase1CompletesAfterDeviceCapabilityStep() {
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = false
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        let m = OnboardingManager(defaults: ud)

        #expect(m.totalStepsInPhase == 3)

        m.advance()
        m.advance()
        #expect(m.currentStep == .p1DeviceCapability)
        #expect(m.requestOpenSettings == true)
        m.requestOpenSettings = false

        m.advance()
        #expect(m.currentStep == nil)
        #expect(m.phaseRaw == 1)
        #expect(m.requestDismissSettings == true)
    }

    @Test func aiCapableRelaunchFromStep3Or4ResetsToStep1() {
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = true
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        ud.set(3, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        #expect(m.stepIndex == 1)
        #expect(m.currentStep == .p1Settings)
    }

    @Test func nonAIRelaunchAtStep2RequestsSettings() {
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = false
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        ud.set(2, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        #expect(m.requestOpenSettings == true)
        #expect(m.currentStep == .p1DeviceCapability)
    }

    @Test func phase2AndSkipUnchanged() {
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = true
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        ud.set(2, forKey: "onboardingPhase")
        ud.set(0, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        #expect(m.currentStep == .p2Progress)

        m.advance()
        #expect(m.currentStep == .p2Moments)

        m.advance()
        #expect(m.phaseRaw == 3)
        #expect(m.stepIndex == 0)

        m.resetOnboarding()
        m.skipOnboarding()
        #expect(m.phaseRaw == 3)
    }
}
