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
    /// The on-device model declined the content (guardrail or refusal).
    case unsafeContent
    /// Generation failed after retry (transient model error, decoding failure, …).
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .unsafeContent:
            "Apple Intelligence declined to analyze this passage."
        case .generationFailed:
            "Couldn't analyze this moment."
        }
    }
}

protocol MomentAnalyzing: Sendable {
    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis

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
    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis {
        throw MomentNamingError.modelUnavailable
    }
}
