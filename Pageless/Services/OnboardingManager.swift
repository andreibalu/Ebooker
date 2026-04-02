//
//  OnboardingManager.swift
//  Pageless
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingManager {

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
            let steps: [OnboardingStep] = [.p1AddButton, .p1Settings, .p1AILink, .p1AIPage]
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
        case .phase1:         return 4
        case .waitingForBook: return 0
        case .phase2:         return 2
        case .completed:      return 0
        }
    }

    var currentPhaseIndex: Int { stepIndex }

    // MARK: - Init

    init() {
        // If relaunched mid-phase1 while on a step requiring the settings sheet,
        // reset to step 1 so the sheet-open sequence replays cleanly.
        if Phase(rawValue: phaseRaw) == .phase1, stepIndex >= 2 {
            stepIndex = 1
        }
    }

    // MARK: - Actions

    func advance() {
        switch phase {
        case .phase1:
            switch stepIndex {
            case 0: // p1AddButton → p1Settings
                stepIndex = 1
            case 1: // p1Settings → open settings sheet, then p1AILink
                stepIndex = 2
                requestOpenSettings = true
            case 2: // p1AILink → navigate to AI settings, then p1AIPage
                stepIndex = 3
                requestNavigateToAISettings = true
            case 3: // p1AIPage done → dismiss sheet, enter waiting phase
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
