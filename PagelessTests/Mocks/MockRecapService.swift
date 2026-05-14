//
//  MockRecapService.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

final class MockRecapService: RecapProviding, @unchecked Sendable {
    var recapToReturn = "Mock recap of recent events."
    var progressHeadlineToReturn: String?
    var shouldThrow = false

    var comebackLocationToReturn = "the abandoned manor"
    var comebackCharactersToReturn = ["Alice"]
    var comebackSummaryToReturn = "Alice descended into the cellar with a candle. She heard footsteps behind her."
    var shouldThrowOnComeback = false

    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        if shouldThrow { throw RecapError.modelUnavailable }
        let headline = includeProgressHeadline ? (progressHeadlineToReturn ?? "Left mid chase scene") : nil
        return RecapGenerationResult(recap: recapToReturn, progressHeadline: headline)
    }

    func generateComebackRecap(
        transcript: String,
        audiobookTitle: String?
    ) async throws -> ComebackRecapResult {
        if shouldThrowOnComeback { throw RecapError.modelUnavailable }
        return ComebackRecapResult(
            location: comebackLocationToReturn,
            characters: comebackCharactersToReturn,
            summary: comebackSummaryToReturn
        )
    }
}
