//
//  MockMomentAnalyzer.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

final class MockMomentAnalyzer: MomentAnalyzing, @unchecked Sendable {
    var analysisToReturn: MomentAnalysis?
    var shouldThrow = false
    var errorToThrow: Error?
    var prewarmCallCount = 0

    func prewarm() { prewarmCallCount += 1 }

    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis {
        if let errorToThrow { throw errorToThrow }
        if shouldThrow { throw MomentNamingError.modelUnavailable }
        return analysisToReturn ?? MomentAnalysis(
            name: "Test Moment",
            note: "Test note",
            categories: [.dialogue],
            quoteLine: "A test quote",
            characters: ["Alice"],
            mood: .mysterious
        )
    }
}
