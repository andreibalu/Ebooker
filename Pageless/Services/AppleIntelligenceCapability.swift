//
//  AppleIntelligenceCapability.swift
//  Pageless
//

import Foundation
import FoundationModels
import Speech

/// Four real states the AI Settings UI cares about. Used to drive Buy-button
/// visibility/enablement and explanatory copy.
enum AIAvailabilityState: Equatable {
    /// Apple Intelligence is on and the model is available. Buy enabled.
    case ready
    /// Hardware + OS support Apple Intelligence but the user hasn't turned it on
    /// (or the model is still loading). Buy visible but disabled until activated.
    case needsActivation
    /// Hardware is Apple Intelligence–capable but the device is running an iOS
    /// version older than 26. Buy hidden; user is told to update iOS.
    case needsIOSUpgrade
    /// This iPhone can't run Apple Intelligence at all (incompatible hardware
    /// regardless of iOS version). Buy hidden.
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
        case .needsIOSUpgrade:
            return "AI features require iOS 26 or later. Update iOS in Settings → General → Software Update, then return here to unlock."
        case .unsupportedDevice:
            return "AI features aren't supported on this iPhone."
        }
    }
}

/// Checks whether the device supports Apple Intelligence and Smart Moment Naming.
/// Stays callable on iOS 18+ — below iOS 26 it reports `.needsIOSUpgrade` for
/// AI-capable hardware (iPhone 15 Pro and later) and `.unsupportedDevice` for the rest.
enum AppleIntelligenceCapability {
    /// Whether the foundational local model is available for Smart Moment Naming.
    /// Requires: iOS 26+, compatible device, Apple Intelligence enabled, and speech
    /// recognition available.
    static var isSmartNamingAvailable: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable && isSpeechRecognitionAvailable
        }
        return false
    }

    /// High-level state for AI Settings UI. Collapses `.modelNotReady` and "AI off in Settings"
    /// into a single `.needsActivation` bucket because both resolve via the same user action.
    static var availabilityState: AIAvailabilityState {
        guard #available(iOS 26, *) else {
            return hardwareSupportsAppleIntelligence ? .needsIOSUpgrade : .unsupportedDevice
        }
        switch SystemLanguageModel.default.availability {
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

        guard #available(iOS 26, *) else {
            return hardwareSupportsAppleIntelligence
                ? "AI features require iOS 26 or later. Update iOS to unlock."
                : "This device does not support Apple Intelligence."
        }

        switch SystemLanguageModel.default.availability {
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

    /// True when this iPhone's hardware can run Apple Intelligence (independent of iOS version).
    /// Apple Intelligence is supported on iPhone 15 Pro and later. Those map to model identifiers
    /// `iPhone16,1` and up; iPhone 15 / 15 Plus are `iPhone15,4` / `iPhone15,5` and don't qualify.
    /// So the rule is: model identifier `iPhoneN,M` with `N >= 16`.
    static var hardwareSupportsAppleIntelligence: Bool {
        let id = deviceModelIdentifier
        guard id.hasPrefix("iPhone"),
              let comma = id.firstIndex(of: ","),
              let major = Int(id[id.index(id.startIndex, offsetBy: "iPhone".count)..<comma])
        else { return false }
        return major >= 16
    }

    private static var deviceModelIdentifier: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        #endif
    }
}
