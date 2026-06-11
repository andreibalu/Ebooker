//
//  SegmentTranscribing.swift
//  Pageless
//

import Foundation

enum SegmentTranscriptionError: LocalizedError {
    case unsupported
    case invalidRange
    case audioUnreadable
    case localeUnavailable
    case analysisFailed
    case emptyResult

    var errorDescription: String? {
        "Could not transcribe audio."
    }
}

/// Transcribes a time range of an audio file directly — no export step and no
/// speech-recognition permission. Implemented by the iOS 26 SpeechAnalyzer service;
/// callers fall back to `AudioExtracting` + `TranscriptionProviding` on failure.
protocol SegmentTranscribing: Sendable {
    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String
}

/// Default transcriber on iOS versions without SpeechAnalyzer. Always throws, which
/// routes callers onto the legacy export + SFSpeechRecognizer path.
struct UnavailableSegmentTranscriber: SegmentTranscribing {
    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        throw SegmentTranscriptionError.unsupported
    }
}
