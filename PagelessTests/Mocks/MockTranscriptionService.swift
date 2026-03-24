//
//  MockTranscriptionService.swift
//  PagelessTests
//

import Speech
@testable import Pageless

final class MockTranscriptionService: TranscriptionProviding, @unchecked Sendable {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized
    var transcriptToReturn: String = "Mock transcript text"
    var shouldThrow = false

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
    }

    func transcribe(audioURL: URL) async throws -> String {
        if shouldThrow { throw TranscriptionError.recognizerUnavailable }
        return transcriptToReturn
    }
}
