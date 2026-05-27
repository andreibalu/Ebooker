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

    @Test func phase1AdvancesThroughAllFiveSteps() {
        // Phase 1 is unified: same 5 steps for every device. The AI step's copy adapts
        // but the step list does not.
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = true
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        let m = OnboardingManager(defaults: ud)

        #expect(m.currentStep == .p1AddButton)
        #expect(m.totalStepsInPhase == 5)

        m.advance()
        #expect(m.currentStep == .p1Settings)
        #expect(m.requestOpenSettings == false)

        m.advance()
        #expect(m.currentStep == .p1AILink)
        #expect(m.requestOpenSettings == true)
        m.requestOpenSettings = false

        m.advance()
        #expect(m.currentStep == .p1iCloudSync)
        // Sheet stays open between AI and iCloud — no open/dismiss requests should fire.
        #expect(m.requestOpenSettings == false)
        #expect(m.requestDismissSettings == false)

        m.advance()
        #expect(m.currentStep == .p1ReadingStats)
        #expect(m.requestDismissSettings == true)
        m.requestDismissSettings = false

        m.advance()
        #expect(m.currentStep == nil)
        #expect(m.phaseRaw == 1) // waitingForBook
        #expect(m.stepIndex == 0)
    }

    @Test func phase1StepCountIsFiveOnUnsupportedDeviceToo() {
        OnboardingManager._unitTestDeviceSupportsOnboardingAI = false
        defer { OnboardingManager._unitTestDeviceSupportsOnboardingAI = nil }

        let ud = isolatedDefaults()
        let m = OnboardingManager(defaults: ud)

        #expect(m.totalStepsInPhase == 5)
        m.advance()
        m.advance()
        #expect(m.currentStep == .p1AILink) // Same step on unsupported devices; copy adapts.
    }

    @Test func relaunchInsideSettingsSheetRewindsToSettingsStep() {
        // Steps 2 (.p1AILink) and 3 (.p1iCloudSync) live inside the Settings sheet.
        // On relaunch the sheet isn't presented yet, so we rewind to step 1 (.p1Settings).
        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        ud.set(3, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        #expect(m.stepIndex == 1)
        #expect(m.currentStep == .p1Settings)
    }

    @Test func relaunchAtReadingStatsStaysPut() {
        // p1ReadingStats lives on ContentView with the Settings sheet closed —
        // relaunch matches that state, so it should not rewind.
        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        ud.set(4, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        #expect(m.stepIndex == 4)
        #expect(m.currentStep == .p1ReadingStats)
        #expect(m.requestOpenSettings == false)
    }

    @Test func goBackFromReadingStatsReopensSettings() {
        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        ud.set(4, forKey: "onboardingStepIndex")

        let m = OnboardingManager(defaults: ud)
        m.goBack()
        #expect(m.currentStep == .p1iCloudSync)
        #expect(m.requestOpenSettings == true)
    }

    @Test func goBackFromAILinkDismissesSettings() {
        let ud = isolatedDefaults()
        ud.set(0, forKey: "onboardingPhase")
        // Force the manager to step 2 via advance() (init would clamp 2→1).
        let m = OnboardingManager(defaults: ud)
        m.advance() // 0 → 1
        m.advance() // 1 → 2 (.p1AILink), requestOpenSettings = true
        m.requestOpenSettings = false

        m.goBack()
        #expect(m.currentStep == .p1Settings)
        #expect(m.requestDismissSettings == true)
    }

    @Test func phase2AndSkipUnchanged() {
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
