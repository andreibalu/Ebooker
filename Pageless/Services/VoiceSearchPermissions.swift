//
//  VoiceSearchPermissions.swift
//  Pageless
//

import AVFoundation
import Foundation
import Speech

/// Centralised gating for the two permissions CarPlay voice search needs.
/// System prompts can only appear when the iPhone is the active device — never
/// while the user is driving and using CarPlay. The onboarding Permissions scene
/// is the app's only proactive request point; this exposes a synchronous status
/// check for the CarPlay path, which refuses gracefully when not granted.
enum VoiceSearchPermissions {
    enum Status {
        case granted
        case denied
        case notDetermined
    }

    static var status: Status {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission

        if speech == .authorized && mic == .granted { return .granted }
        if speech == .denied || speech == .restricted { return .denied }
        if mic == .denied { return .denied }
        return .notDetermined
    }
}
