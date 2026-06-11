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
