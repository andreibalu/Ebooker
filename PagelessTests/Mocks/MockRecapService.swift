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
    var errorToThrow: Error?

    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        if let errorToThrow { throw errorToThrow }
        if shouldThrow { throw RecapError.modelUnavailable }
        let headline = includeProgressHeadline ? (progressHeadlineToReturn ?? "Left mid chase scene") : nil
        return RecapGenerationResult(recap: recapToReturn, progressHeadline: headline)
    }
}
