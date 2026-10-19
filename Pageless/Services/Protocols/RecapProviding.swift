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
    /// The model refused the passage or tripped a guardrail, even after a retry on a shorter
    /// passage.
    case declined
    /// Generation failed after retry (transient model error, unreadable reply, …).
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .declined:
            "Apple Intelligence couldn't summarize this part of the book. Try again after listening a little further."
        case .generationFailed:
            "Couldn't generate a recap. Please try again."
        }
    }
}

protocol RecapProviding: Sendable {
    func generateRecap(
        transcript: String,
        context: AIPassageContext,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult

    /// Optional: load model resources while the transcript is still being made.
    func prewarm()
}

extension RecapProviding {
    func prewarm() {}
}

/// Default recap provider used on iOS versions without FoundationModels. Always throws;
/// never invoked at runtime because `AppleIntelligenceCapability` reports unsupported there.
struct UnavailableRecapProvider: RecapProviding {
    func generateRecap(
        transcript: String,
        context: AIPassageContext,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        throw RecapError.modelUnavailable
    }
}
