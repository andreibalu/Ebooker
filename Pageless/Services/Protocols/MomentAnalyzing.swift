//
//  MomentAnalyzing.swift
//  Pageless
//

import Foundation

struct MomentAnalysis: Sendable {
    let name: String
    let note: String
    let categories: [MomentCategory]
    let quoteLine: String?
    let characters: [String]
    let mood: MomentMood?
}

enum MomentNamingError: LocalizedError, Equatable {
    case modelUnavailable
    /// The model refused the passage or tripped a guardrail, even after a retry on a shorter
    /// passage. Smart save falls back to `MomentFallbackNamer`.
    case declined
    /// Generation failed after retry (transient model error, unreadable reply, …).
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .declined, .generationFailed:
            "Apple Intelligence couldn't summarize this passage."
        }
    }
}

protocol MomentAnalyzing: Sendable {
    func analyzeMoment(transcript: String, context: AIPassageContext) async throws -> MomentAnalysis

    /// Optional: load model resources ahead of the first `analyzeMoment` call.
    func prewarm()
}

extension MomentAnalyzing {
    func prewarm() {}
}

/// Default analyzer used on iOS versions without FoundationModels. Always throws
/// `.modelUnavailable`; never invoked at runtime because `AppleIntelligenceCapability`
/// reports the AI features as unsupported there.
struct UnavailableMomentAnalyzer: MomentAnalyzing {
    func analyzeMoment(transcript: String, context: AIPassageContext) async throws -> MomentAnalysis {
        throw MomentNamingError.modelUnavailable
    }
}
