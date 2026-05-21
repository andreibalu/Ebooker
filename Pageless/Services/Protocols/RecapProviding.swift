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

enum RecapError: LocalizedError {
    case modelUnavailable
    case noAudioAvailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .noAudioAvailable:
            "No audio available for recap."
        }
    }
}

protocol RecapProviding: Sendable {
    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult
}

/// Default recap provider used on iOS versions without FoundationModels. Always throws;
/// never invoked at runtime because `AppleIntelligenceCapability` reports unsupported there.
struct UnavailableRecapProvider: RecapProviding {
    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        throw RecapError.modelUnavailable
    }
}
