//
//  MockMomentAnalyzer.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

final class MockMomentAnalyzer: MomentAnalyzing, @unchecked Sendable {
    var analysisToReturn: MomentAnalysis?
    var shouldThrow = false

    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis {
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
