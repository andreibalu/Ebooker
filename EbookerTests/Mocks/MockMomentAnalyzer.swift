//
//  MockMomentAnalyzer.swift
//  EbookerTests
//

import Foundation
@testable import Ebooker

final class MockMomentAnalyzer: MomentAnalyzing, @unchecked Sendable {
    var analysisToReturn: MomentNamingService.MomentAnalysis?
    var shouldThrow = false

    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentNamingService.MomentAnalysis {
        if shouldThrow { throw MomentNamingError.modelUnavailable }
        return analysisToReturn ?? MomentNamingService.MomentAnalysis(
            name: "Test Moment",
            note: "Test note",
            categories: [.dialogue],
            quoteLine: "A test quote",
            characters: ["Alice"],
            mood: .mysterious
        )
    }
}
