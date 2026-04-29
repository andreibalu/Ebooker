//
//  VoiceSearchPermissions.swift
//  Pageless
//

import AVFoundation
import Foundation
import Speech

/// Centralised gating for the two permissions CarPlay voice search needs.
/// System prompts can only appear when the iPhone is the active device — never
/// while the user is driving and using CarPlay — so we prime both up front and
/// expose a synchronous status check for the CarPlay path.
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

    /// Requests both permissions on the iPhone. Safe to call repeatedly —
    /// iOS only shows the system alert the first time. Must be called while
    /// the phone (not CarPlay) is the foreground experience so the user sees it.
    static func primeIfNeeded() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        }
    }
}
