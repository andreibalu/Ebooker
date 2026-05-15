//
//  RecapProviding.swift
//  Pageless
//

import Foundation

struct RecapGenerationResult: Sendable {
    var recap: String
    /// Very short UI headline (e.g. 3–4 words); only set when requested.
    var progressHeadline: String?
}

protocol RecapProviding: Sendable {
    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult
}
