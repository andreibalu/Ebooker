//
//  AppleIntelligenceCapability.swift
//  Ebooker
//

import Foundation
import FoundationModels
import Speech

/// Checks whether the device supports Apple Intelligence and Smart Moment Naming.
enum AppleIntelligenceCapability {
    private static let model = SystemLanguageModel.default

    /// Whether the foundational local model is available for Smart Moment Naming.
    /// Requires: compatible device, Apple Intelligence enabled, and speech recognition available.
    static var isSmartNamingAvailable: Bool {
        model.isAvailable && isSpeechRecognitionAvailable
    }

    /// Detailed availability status for UI messaging.
    static var availability: SystemLanguageModel.Availability {
        model.availability
    }

    /// Human-readable reason when Smart Naming is unavailable.
    static var unavailabilityReason: String? {
        guard !isSmartNamingAvailable else { return nil }

        switch model.availability {
        case .available:
            return isSpeechRecognitionAvailable ? nil : "Speech recognition is not available."
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use this feature."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still loading. Try again in a moment."
        case .unavailable:
            return "Apple Intelligence is not available."
        }
    }

    private static var isSpeechRecognitionAvailable: Bool {
        SFSpeechRecognizer(locale: Locale.current)?.isAvailable ?? false
    }
}
