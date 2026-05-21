//
//  OnboardingStep.swift
//  Pageless
//

import Foundation

enum OnboardingStep: String, CaseIterable {
    case p1AddButton
    case p1Settings
    case p1AILink
    case p1AIPage
    /// Shown on devices that cannot run on-device AI; anchored to the Settings notice.
    case p1DeviceCapability
    case p2Progress
    case p2Moments

    func title(deviceSupportsOnboardingAI: Bool, requiresIOSUpgrade: Bool = false) -> String {
        switch self {
        case .p1AddButton:   "Import Your First Book"
        case .p1Settings:    deviceSupportsOnboardingAI ? "Playback & AI Settings" : "Playback Settings"
        case .p1AILink:      requiresIOSUpgrade ? "AI Needs iOS 26" : "On-Device AI"
        case .p1AIPage:      requiresIOSUpgrade ? "Update iOS to Unlock" : "Smart Features"
        case .p1DeviceCapability: "Not on this device"
        case .p2Progress:    "Track Your Progress"
        case .p2Moments:     "Save & Filter Moments"
        }
    }

    func body(deviceSupportsOnboardingAI: Bool, requiresIOSUpgrade: Bool = false) -> String {
        switch self {
        case .p1AddButton:
            "Tap here to add audiobooks from Files. Works with M4B, MP3, M4A, and full chapter folders."
        case .p1Settings:
            if deviceSupportsOnboardingAI {
                "Customize resume offset, skip intervals, and explore AI-powered features."
            } else {
                "Tune resume and skip intervals here."
            }
        case .p1AILink:
            if requiresIOSUpgrade {
                "Your iPhone supports Apple Intelligence, but it needs iOS 26 or later. Update in Settings → General → Software Update to unlock smart moment naming and progress recaps."
            } else {
                "Apple Intelligence powers smart moment naming and progress recaps — all processed privately on-device."
            }
        case .p1AIPage:
            if requiresIOSUpgrade {
                "Once you're on iOS 26, come back here to turn on smart moment naming and progress recaps. A free trial is included."
            } else {
                "Toggle individual features here. A free trial is included so you can try before unlocking."
            }
        case .p1DeviceCapability:
            "This device doesn’t support on-device AI. Purchases stay on your Apple ID if you use a supported device later."
        case .p2Progress:
            if requiresIOSUpgrade {
                "Tap Play to start listening. Your progress is saved automatically — once you're on iOS 26, an AI recap of where you left off becomes available here."
            } else if deviceSupportsOnboardingAI {
                "Tap Play to start listening. Your progress is saved automatically — once you've listened a bit, a sparkle button appears here for an AI recap of where you left off."
            } else {
                "Tap Play to start listening. Your progress is saved automatically."
            }
        case .p2Moments:
            if requiresIOSUpgrade {
                "Bookmark moments while listening. On iOS 26, AI adds categories and mood automatically — use filters to find them either way."
            } else if deviceSupportsOnboardingAI {
                "Bookmark moments while listening. AI adds categories and mood — use filters to find exactly what you need."
            } else {
                "Bookmark moments while listening and use filters to find them later."
            }
        }
    }

    var buttonLabel: String {
        switch self {
        case .p1AddButton, .p1Settings, .p1AILink:  "Next"
        case .p1AIPage, .p1DeviceCapability:       "Got It"
        case .p2Progress:                            "Next"
        case .p2Moments:                             "Start Exploring"
        }
    }
}
