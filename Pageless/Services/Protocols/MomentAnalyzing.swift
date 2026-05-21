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

enum MomentNamingError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        }
    }
}

protocol MomentAnalyzing: Sendable {
    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis
}

/// Default analyzer used on iOS versions without FoundationModels. Always throws
/// `.modelUnavailable`; never invoked at runtime because `AppleIntelligenceCapability`
/// reports the AI features as unsupported there.
struct UnavailableMomentAnalyzer: MomentAnalyzing {
    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis {
        throw MomentNamingError.modelUnavailable
    }
}
