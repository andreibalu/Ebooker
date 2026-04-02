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
    case p2Progress
    case p2Moments

    var title: String {
        switch self {
        case .p1AddButton:   "Import Your First Book"
        case .p1Settings:    "Playback & AI Settings"
        case .p1AILink:      "On-Device AI"
        case .p1AIPage:      "Smart Features"
        case .p2Progress:    "Track Your Progress"
        case .p2Moments:     "Save & Filter Moments"
        }
    }

    var body: String {
        switch self {
        case .p1AddButton:
            "Tap here to add audiobooks from Files. Works with M4B, MP3, M4A, and full chapter folders."
        case .p1Settings:
            "Customize resume offset, skip intervals, and explore AI-powered features."
        case .p1AILink:
            "Apple Intelligence powers smart moment naming and progress recaps — all processed privately on-device."
        case .p1AIPage:
            "Toggle individual features here. A free trial is included so you can try before unlocking."
        case .p2Progress:
            "Tap Play to start listening. Your progress is saved automatically — once you've listened a bit, a sparkle button appears here for an AI recap of where you left off."
        case .p2Moments:
            "Bookmark moments while listening. AI adds categories and mood — use filters to find exactly what you need."
        }
    }

    var buttonLabel: String {
        switch self {
        case .p1AddButton, .p1Settings, .p1AILink:  "Next"
        case .p1AIPage:                              "Got It"
        case .p2Progress:                            "Next"
        case .p2Moments:                             "Start Exploring"
        }
    }
}
