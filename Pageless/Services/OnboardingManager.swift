//
//  OnboardingManager.swift
//  Pageless
//
//  Gates the welcome onboarding flow (`OnboardingFlowView`). The flow is shown once on first launch
//  and again whenever the user resets it from Settings. All preference choices are persisted by the
//  flow itself (it binds straight to the app's @AppStorage keys); this manager only tracks whether the
//  flow still needs to be shown.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingManager {

    private let defaults: UserDefaults

    private enum Keys {
        static let complete = "onboardingComplete"
        /// Legacy phase key from the previous spotlight walkthrough. `3` meant "completed".
        static let legacyPhase = "onboardingPhase"
    }

    /// True once the user has finished (or skipped) onboarding. While false, the flow is presented.
    var isComplete: Bool {
        didSet { defaults.set(isComplete, forKey: Keys.complete) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.complete) != nil {
            isComplete = defaults.bool(forKey: Keys.complete)
        } else {
            // Migration: users who finished the old walkthrough (legacy phase == completed) don't
            // see the new onboarding. Everyone else (fresh installs, mid-walkthrough) does.
            isComplete = defaults.integer(forKey: Keys.legacyPhase) == 3
        }
    }

    /// Mark onboarding finished — called when the user taps "Open Library".
    func complete() {
        isComplete = true
    }

    /// Re-show the onboarding flow (Settings → "Reset Onboarding").
    func reset() {
        isComplete = false
    }
}
