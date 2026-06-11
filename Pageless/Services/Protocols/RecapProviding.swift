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

enum RecapError: LocalizedError, Equatable {
    case modelUnavailable
    case noAudioAvailable
    /// The on-device model declined the content (guardrail or refusal).
    case unsafeContent
    /// Generation failed after retry (transient model error, decoding failure, …).
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .noAudioAvailable:
            "No audio available for recap."
        case .unsafeContent:
            "Apple Intelligence declined to summarize this passage."
        case .generationFailed:
            "Couldn't generate a recap. Please try again."
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
