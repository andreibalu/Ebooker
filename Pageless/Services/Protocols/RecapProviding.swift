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

/// Anchor + 2-sentence summary used by the welcome-back prompt.
struct ComebackRecapResult: Sendable {
    var location: String
    var characters: [String]
    var summary: String
}

protocol RecapProviding: Sendable {
    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult

    func generateComebackRecap(
        transcript: String,
        audiobookTitle: String?
    ) async throws -> ComebackRecapResult
}
