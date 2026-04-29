//
//  CarPlayVoiceSearch.swift
//  Pageless
//

import AVFoundation
import OSLog
import Speech

private let voiceLog = Logger(subsystem: "andreibaludev.Pageless", category: "CarPlayVoice")

/// Hands-free dictation for CarPlay: streams microphone audio into Speech and
/// auto-finishes after a short silence window. Single-shot per `recognize()` call.
@MainActor
final class CarPlayVoiceSearch {
    enum VoiceError: LocalizedError {
        case speechAuthDenied
        case microphoneDenied
        case recognizerUnavailable
        case audioEngineFailed
        case noSpeechDetected

        var errorDescription: String? {
            switch self {
            case .speechAuthDenied: "Speech recognition permission denied."
            case .microphoneDenied: "Microphone permission denied."
            case .recognizerUnavailable: "Speech recognition is not available right now."
            case .audioEngineFailed: "Could not start recording."
            case .noSpeechDetected: "I didn't catch that. Try again."
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var silenceTimer: Task<Void, Never>?
    private var hardStopTimer: Task<Void, Never>?

    private var lastTranscript: String = ""
    private var continuation: CheckedContinuation<String, Error>?

    /// Records microphone audio and returns the transcribed text.
    /// Auto-stops 1.5 s after the last recognized word, or 6 s after start.
    func recognize() async throws -> String {
        try await ensureAuthorization()

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        lastTranscript = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            voiceLog.error("audioEngine.start failed: \(String(describing: error), privacy: .public)")
            cleanup()
            throw VoiceError.audioEngineFailed
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            self.continuation = cont
            self.startHardStopTimer()
            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    self?.handleRecognition(result: result, error: error)
                }
            }
        }
    }

    func cancel() {
        finish(.failure(VoiceError.noSpeechDetected))
    }

    // MARK: - Private

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if text != lastTranscript {
                lastTranscript = text
                resetSilenceTimer()
            }
            if result.isFinal {
                finish(.success(text))
                return
            }
        }
        if error != nil {
            // Speech ends with an error after `endAudio()` even on success — treat captured text as the answer.
            if !lastTranscript.isEmpty {
                finish(.success(lastTranscript))
            } else {
                finish(.failure(VoiceError.noSpeechDetected))
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            self.recognitionRequest?.endAudio()
            if !self.lastTranscript.isEmpty {
                self.finish(.success(self.lastTranscript))
            }
        }
    }

    private func startHardStopTimer() {
        hardStopTimer?.cancel()
        hardStopTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            self.recognitionRequest?.endAudio()
            if self.lastTranscript.isEmpty {
                self.finish(.failure(VoiceError.noSpeechDetected))
            } else {
                self.finish(.success(self.lastTranscript))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cleanup()

        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                cont.resume(throwing: VoiceError.noSpeechDetected)
            } else {
                cont.resume(returning: trimmed)
            }
        case .failure(let error):
            cont.resume(throwing: error)
        }
    }

    private func cleanup() {
        silenceTimer?.cancel()
        silenceTimer = nil
        hardStopTimer?.cancel()
        hardStopTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Restore the audiobook playback session so playback isn't stuck in record mode.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func ensureAuthorization() async throws {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        guard speechStatus == .authorized else { throw VoiceError.speechAuthDenied }

        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
        guard micGranted else { throw VoiceError.microphoneDenied }
    }
}
