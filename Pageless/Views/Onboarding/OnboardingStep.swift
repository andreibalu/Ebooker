//
//  OnboardingStep.swift
//  Pageless
//

import Foundation

enum OnboardingStep: String, CaseIterable {
    case p1AddButton
    case p1Settings
    /// Apple Intelligence hero card in Settings. Copy branches on whether the device/OS supports AI.
    case p1AILink
    /// iCloud Sync hero card in Settings.
    case p1iCloudSync
    /// Mock-card preview of the Reading Activity stats — last step of phase 1.
    case p1ReadingStats
    case p2Progress
    case p2Moments

    func title(deviceSupportsOnboardingAI: Bool, requiresIOSUpgrade: Bool = false) -> String {
        switch self {
        case .p1AddButton:   "Import Your First Book"
        case .p1Settings:    "Playback & Features"
        case .p1AILink:      deviceSupportsOnboardingAI && !requiresIOSUpgrade ? "On-Device AI" : "AI Features"
        case .p1iCloudSync:  "iCloud Sync"
        case .p1ReadingStats: "Your Listening Journey"
        case .p2Progress:    "Track Your Progress"
        case .p2Moments:     "Save & Filter Moments"
        }
    }

    func body(deviceSupportsOnboardingAI: Bool, requiresIOSUpgrade: Bool = false) -> String {
        switch self {
        case .p1AddButton:
            "Tap here to add audiobooks from Files. Works with M4B, MP3, M4A, and full chapter folders."
        case .p1Settings:
            "Customize resume offset, skip intervals, and explore optional features."
        case .p1AILink:
            if !deviceSupportsOnboardingAI || requiresIOSUpgrade {
                "Smart moment naming and progress recaps. Requires iOS 26 and an Apple Intelligence-compatible iPhone."
            } else {
                "Apple Intelligence powers smart moment naming and progress recaps — all processed privately on-device."
            }
        case .p1iCloudSync:
            "Keep your library, progress, moments, and listening stats synced across all your devices."
        case .p1ReadingStats:
            "Track time listened, daily streaks, and your favorite hours. Tap the card any time for the full picture of your listening journal."
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
        case .p1AddButton, .p1Settings, .p1AILink, .p1iCloudSync:  "Next"
        case .p1ReadingStats:                                      "Got It"
        case .p2Progress:                                          "Next"
        case .p2Moments:                                           "Start Exploring"
        }
    }
}
