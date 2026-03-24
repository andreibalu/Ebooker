//
//  TranscriptionProviding.swift
//  Pageless
//

import Speech

protocol TranscriptionProviding: Sendable {
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    func transcribe(audioURL: URL) async throws -> String
}
