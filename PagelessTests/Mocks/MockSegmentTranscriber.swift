//
//  MockSegmentTranscriber.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

final class MockSegmentTranscriber: SegmentTranscribing, @unchecked Sendable {
    var transcriptToReturn = "Mock segment transcript"
    var shouldThrow = false
    var callCount = 0
    var lastRange: (start: Double, end: Double)?

    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        callCount += 1
        lastRange = (startSeconds, endSeconds)
        if shouldThrow { throw SegmentTranscriptionError.audioUnreadable }
        return transcriptToReturn
    }
}

/// Holds the primary transcription path open until the test task is cancelled.
/// The real SpeechAnalyzer service has the same cancellation contract, while
/// this helper gives view-model tests a deterministic synchronization point.
final class BlockingSegmentTranscriber: SegmentTranscribing, @unchecked Sendable {
    private let startedStream: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init() {
        (startedStream, startedContinuation) = AsyncStream<Void>.makeStream()
    }

    func waitUntilStarted() async {
        for await _ in startedStream {
            return
        }
    }

    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        startedContinuation.yield(())
        try await Task.sleep(for: .seconds(60))
        return "unexpected transcript"
    }
}
