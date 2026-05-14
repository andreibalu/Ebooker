//
//  ComebackVoicePrompt.swift
//  Pageless
//

import AVFoundation
import Foundation
import OSLog

private let voicePromptLog = Logger(subsystem: "andreibaludev.Pageless", category: "ComebackVoice")

/// Siri-launched welcome-back recap. Speaks the prompt via TTS and listens for a
/// yes/no answer; if the user says yes, speaks the recap; either way, starts playback.
///
/// Designed for the headphones + screen-off case. Falls back to silent playback if
/// any step fails (permissions, mic, recognition) — we never block the user from
/// resuming their book.
@MainActor
enum ComebackVoicePrompt {
    static func run(
        audiobook: Audiobook,
        coordinator: ComebackPromptCoordinator,
        player: AudioPlayerManager
    ) async {
        // Bail out fast if the route doesn't support speaking to the listener
        // (e.g. no outputs available). Built-in speaker is fine — Siri normally
        // routes there for spoken responses.
        guard hasUsableAudioOutput() else {
            await player.startPlaybackFromSavedProgress(for: audiobook)
            return
        }

        guard VoiceSearchPermissions.status == .granted else {
            await player.startPlaybackFromSavedProgress(for: audiobook)
            return
        }

        // Generate the recap up front so the spoken "yes" lands on a ready summary.
        let recap = await coordinator.generateRecap(for: audiobook)

        let speaker = SpeechPromptSpeaker()
        await speaker.speak("Want a quick recap of where you left off?")

        let listener = CarPlayVoiceSearch()
        var saidYes: Bool = false
        do {
            let answer = try await listener.recognize()
            saidYes = answerSaysYes(answer)
        } catch {
            voicePromptLog.info("voice answer not captured: \(String(describing: error), privacy: .public)")
            saidYes = false
        }

        if saidYes, let recap, !recap.summary.isEmpty {
            let anchor = ComebackPromptSheet.anchorLine(recap)
            let line = anchor.isEmpty ? recap.summary : "\(anchor) \(recap.summary)"
            await speaker.speak(line)
        }

        // Hand the route back to playback before we activate the audiobook session.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        await player.startPlaybackFromSavedProgress(for: audiobook)
    }

    static func answerSaysYes(_ raw: String) -> Bool {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let yesWords: Set<String> = ["yes", "yeah", "yep", "sure", "okay", "ok", "please", "go ahead", "do it"]
        let noWords: Set<String> = ["no", "nope", "skip", "don't", "not now", "cancel", "stop"]
        for word in noWords where normalized.contains(word) { return false }
        for word in yesWords where normalized.contains(word) { return true }
        return false
    }

    private static func hasUsableAudioOutput() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return !outputs.isEmpty
    }
}

/// Thin TTS wrapper. Speaks via `AVSpeechSynthesizer` and waits an estimated
/// duration (≈2.5 words/sec + buffer) so we don't entangle with the delegate's
/// actor isolation. Audio session is set to `.playback` ducking before speaking
/// so any other audio drops down.
@MainActor
final class SpeechPromptSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) async {
        guard !text.isEmpty else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)

        let words = text.split(whereSeparator: \.isWhitespace).count
        let estimatedSeconds = max(1.0, Double(words) / 2.5 + 0.6)
        try? await Task.sleep(for: .seconds(estimatedSeconds))
    }
}
