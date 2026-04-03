//
//  OnboardingManager.swift
//  Pageless
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingManager {

    /// Phase 1 includes AI Settings steps only on devices that can purchase / use the on-device AI stack.
    var deviceSupportsOnboardingAI: Bool {
        AppleIntelligenceCapability.canPurchaseAIUnlockOnThisDevice
    }

    private var phase1Steps: [OnboardingStep] {
        deviceSupportsOnboardingAI
            ? [.p1AddButton, .p1Settings, .p1AILink, .p1AIPage]
            : [.p1AddButton, .p1Settings, .p1DeviceCapability]
    }

    // MARK: - Stored properties (tracked by @Observable)

    var phaseRaw: Int = UserDefaults.standard.integer(forKey: "onboardingPhase") {
        didSet { UserDefaults.standard.set(phaseRaw, forKey: "onboardingPhase") }
    }

    var stepIndex: Int = UserDefaults.standard.integer(forKey: "onboardingStepIndex") {
        didSet { UserDefaults.standard.set(stepIndex, forKey: "onboardingStepIndex") }
    }

    // MARK: - Navigation Commands (observed by views)

    var requestOpenSettings = false
    var requestNavigateToAISettings = false
    var requestDismissSettings = false

    // MARK: - Phase

    private enum Phase: Int {
        case phase1 = 0
        case waitingForBook = 1
        case phase2 = 2
        case completed = 3
    }

    private var phase: Phase {
        get { Phase(rawValue: phaseRaw) ?? .completed }
        set { phaseRaw = newValue.rawValue }
    }

    // MARK: - Current Step

    var currentStep: OnboardingStep? {
        switch phase {
        case .phase1:
            let steps = phase1Steps
            guard stepIndex < steps.count else { return nil }
            return steps[stepIndex]
        case .waitingForBook:
            return nil
        case .phase2:
            let steps: [OnboardingStep] = [.p2Progress, .p2Moments]
            guard stepIndex < steps.count else { return nil }
            return steps[stepIndex]
        case .completed:
            return nil
        }
    }

    var totalStepsInPhase: Int {
        switch phase {
        case .phase1:         return phase1Steps.count
        case .waitingForBook: return 0
        case .phase2:         return 2
        case .completed:      return 0
        }
    }

    var currentPhaseIndex: Int { stepIndex }

    // MARK: - Init

    init() {
        guard Phase(rawValue: phaseRaw) == .phase1 else { return }

        let maxIndex = phase1Steps.count - 1
        if stepIndex > maxIndex {
            stepIndex = maxIndex
        }

        // Relaunch mid-phase1 on AI-capable devices: replay from settings so the sheet + AI navigation reopen cleanly.
        if deviceSupportsOnboardingAI, stepIndex >= 2 {
            stepIndex = 1
        }

        // Non-AI path: step 2 is only meaningful with Settings open (anchor for .p1DeviceCapability).
        if !deviceSupportsOnboardingAI, stepIndex == 2 {
            requestOpenSettings = true
        }
    }

    // MARK: - Actions

    func advance() {
        switch phase {
        case .phase1:
            switch stepIndex {
            case 0:
                stepIndex = 1
            case 1:
                stepIndex = 2
                requestOpenSettings = true
            case 2:
                if deviceSupportsOnboardingAI {
                    stepIndex = 3
                    requestNavigateToAISettings = true
                } else {
                    phase = .waitingForBook
                    stepIndex = 0
                    requestDismissSettings = true
                }
            case 3:
                guard deviceSupportsOnboardingAI else { break }
                phase = .waitingForBook
                stepIndex = 0
                requestDismissSettings = true
            default:
                break
            }
        case .phase2:
            switch stepIndex {
            case 0: // p2Progress → p2Moments
                stepIndex = 1
            case 1: // p2Moments done → completed
                phase = .completed
                stepIndex = 0
            default:
                break
            }
        default:
            break
        }
    }

    func goBack() {
        guard stepIndex > 0 else { return }
        if phase == .phase1, stepIndex == 2, !deviceSupportsOnboardingAI {
            requestDismissSettings = true
        }
        stepIndex -= 1
    }

    func skipOnboarding() {
        phase = .completed
        stepIndex = 0
    }

    func notifyBookImported() {
        guard phase == .waitingForBook else { return }
        phase = .phase2
        stepIndex = 0
    }

    func resetOnboarding() {
        phase = .phase1
        stepIndex = 0
    }
}
