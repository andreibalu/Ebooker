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
    var authorizationRequestCount = 0
    var transcribeCallCount = 0

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationRequestCount += 1
        return authorizationStatus
    }

    func transcribe(audioURL: URL) async throws -> String {
        transcribeCallCount += 1
        if shouldThrow { throw TranscriptionError.recognizerUnavailable }
        return transcriptToReturn
    }
}
