//
//  MockAudioExtractor.swift
//  EbookerTests
//

import Foundation
@testable import Ebooker

final class MockAudioExtractor: AudioExtracting, @unchecked Sendable {
    var urlToReturn = URL(fileURLWithPath: "/tmp/mock-audio.m4a")
    var shouldThrow = false

    func extractSegment(from fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> URL {
        if shouldThrow { throw AudioExtractionError.exportFailed }
        return urlToReturn
    }

    func extractSegment(from fileURL: URL, currentTime: Double, duration: Double) async throws -> URL {
        if shouldThrow { throw AudioExtractionError.exportFailed }
        return urlToReturn
    }
}
