//
//  AppleIntelligenceCapability.swift
//  Pageless
//

import Foundation
import FoundationModels
import Speech

/// Three real states the AI Settings UI cares about. Used to drive Buy-button
/// visibility/enablement and explanatory copy.
enum AIAvailabilityState: Equatable {
    /// Apple Intelligence is on and the model is available. Buy enabled.
    case ready
    /// Hardware + OS support Apple Intelligence but the user hasn't turned it on
    /// (or the model is still loading). Buy visible but disabled until activated.
    case needsActivation
    /// This iPhone can't run Apple Intelligence at all. Buy hidden.
    case unsupportedDevice

    /// Only `.ready` allows purchase — anything else means the unlock wouldn't be usable.
    var allowsPurchase: Bool { self == .ready }

    /// Short user-facing explanation. Empty in `.ready` since the Buy block carries its own copy.
    var explanation: String {
        switch self {
        case .ready:
            return ""
        case .needsActivation:
            return "Apple Intelligence isn't turned on. Open iOS Settings → Apple Intelligence & Siri to enable it, then return here to unlock."
        case .unsupportedDevice:
            return "AI features aren't supported on this iPhone."
        }
    }
}

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

    /// High-level state for AI Settings UI. Collapses `.modelNotReady` and "AI off in Settings"
    /// into a single `.needsActivation` bucket because both resolve via the same user action.
    static var availabilityState: AIAvailabilityState {
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unsupportedDevice
        case .unavailable(.appleIntelligenceNotEnabled),
             .unavailable(.modelNotReady):
            return .needsActivation
        case .unavailable:
            return .needsActivation
        }
    }

    /// Whether this device can buy the AI unlock right now. Only `.ready` qualifies —
    /// purchasing on `.needsActivation` would leave the user unable to use what they paid for.
    static var canPurchaseAIUnlockOnThisDevice: Bool {
        availabilityState == .ready
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
