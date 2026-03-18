//
//  MockRecapService.swift
//  EbookerTests
//

import Foundation
@testable import Ebooker

final class MockRecapService: RecapProviding, @unchecked Sendable {
    var recapToReturn = "Mock recap of recent events."
    var shouldThrow = false

    func generateRecap(transcript: String, audiobookTitle: String?) async throws -> String {
        if shouldThrow { throw RecapError.modelUnavailable }
        return recapToReturn
    }
}
