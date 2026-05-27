//
//  OnboardingManager.swift
//  Pageless
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingManager {

    /// When set, overrides hardware for unit tests. Must be `nil` in production; only tests assign this.
    static var _unitTestDeviceSupportsOnboardingAI: Bool?

    /// Phase 1 includes AI Settings steps only on devices that can purchase / use the on-device AI stack.
    var deviceSupportsOnboardingAI: Bool {
        if let override = Self._unitTestDeviceSupportsOnboardingAI {
            return override
        }
        // Includes `.needsActivation` and `.needsIOSUpgrade`: hardware can handle AI, so the user
        // walks the AI onboarding and gets told how to activate Apple Intelligence or update iOS.
        return AppleIntelligenceCapability.availabilityState != .unsupportedDevice
    }

    /// True when hardware supports Apple Intelligence but the OS is below iOS 26.
    /// Onboarding copy branches on this so the AI steps point the user at Software Update
    /// instead of describing features they can't use yet.
    var requiresIOSUpgradeForAI: Bool {
        AppleIntelligenceCapability.availabilityState == .needsIOSUpgrade
    }

    /// Phase 1 is a single 5-step path for all devices. The AI step's body copy adapts to whether the
    /// hardware/OS can run Apple Intelligence — but the step itself is always shown so every user
    /// learns the feature exists.
    private let phase1Steps: [OnboardingStep] = [
        .p1AddButton, .p1Settings, .p1AILink, .p1iCloudSync, .p1ReadingStats
    ]

    // MARK: - Stored properties (tracked by @Observable)

    private let defaults: UserDefaults

    var phaseRaw: Int {
        didSet { defaults.set(phaseRaw, forKey: Keys.phase) }
    }

    var stepIndex: Int {
        didSet { defaults.set(stepIndex, forKey: Keys.step) }
    }

    private enum Keys {
        static let phase = "onboardingPhase"
        static let step = "onboardingStepIndex"
    }

    // MARK: - Navigation Commands (observed by views)

    var requestOpenSettings = false
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        phaseRaw = defaults.integer(forKey: Keys.phase)
        stepIndex = defaults.integer(forKey: Keys.step)

        guard Phase(rawValue: phaseRaw) == .phase1 else { return }

        let maxIndex = phase1Steps.count - 1
        if stepIndex > maxIndex {
            stepIndex = maxIndex
        }

        // Steps 2 (.p1AILink) and 3 (.p1iCloudSync) are anchored to hero cards inside the Settings sheet.
        // On relaunch the sheet isn't presented, so rewind to step 1 (.p1Settings) and let the user
        // replay the open-Settings transition naturally.
        if stepIndex >= 2, stepIndex <= 3 {
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
            case 1: // p1Settings → p1AILink (open the sheet so the AI hero card is on screen)
                stepIndex = 2
                requestOpenSettings = true
            case 2: // p1AILink → p1iCloudSync (sheet stays open, anchor shifts to iCloud card)
                stepIndex = 3
            case 3: // p1iCloudSync → p1ReadingStats (close the sheet so the activity card is on screen)
                stepIndex = 4
                requestDismissSettings = true
            case 4: // p1ReadingStats done → waitingForBook
                phase = .waitingForBook
                stepIndex = 0
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
        if phase == .phase1 {
            switch stepIndex {
            case 2:
                // p1AILink → p1Settings: dismiss the sheet so the gear button anchor is visible again.
                requestDismissSettings = true
            case 4:
                // p1ReadingStats → p1iCloudSync: the sheet was dismissed on entering ReadingStats; reopen it.
                requestOpenSettings = true
            default:
                break
            }
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
