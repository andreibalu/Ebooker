//
//  MomentNamingService.swift
//  Ebooker
//

import Foundation
import FoundationModels

/// Uses the foundational local model (SystemLanguageModel.default) to generate
/// a concise moment name from an audiobook transcript.
struct MomentNamingService: MomentAnalyzing {
    @Generable(description: "Analysis of an audiobook moment bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "3–5 word phrase capturing the key concept or event from the transcript")
        var momentName: String

        @Guide(description: "3–4 sentence description providing detailed context about what is happening at this point in the audiobook, what led to it, and why it matters")
        var momentNote: String

        @Guide(description: "1-3 categories from: dialogue, action, plotTwist, characterIntro, worldBuilding, quote, reflection, humor, tension, romance")
        var categories: [String]

        @Guide(description: "The single most memorable or quotable line from the transcript, verbatim (approximately 50 words max)")
        var quoteLine: String

        @Guide(description: "Character names mentioned or speaking in the transcript")
        var characters: [String]

        @Guide(description: "Overall mood: tense, funny, sad, romantic, inspirational, mysterious, peaceful, or dramatic")
        var mood: String
    }

    struct MomentAnalysis {
        let name: String
        let note: String
        let categories: [MomentCategory]
        let quoteLine: String?
        let characters: [String]
        let mood: MomentMood?
    }

    private let instructions = Instructions(
        "You are an assistant that analyzes audiobook bookmarks. " +
        "Given a transcript excerpt, produce: " +
        "1) A concise 3–5 word title-case name. " +
        "2) A 3–4 sentence note describing what is happening, what led up to it, and why it matters. " +
        "3) 1–3 categories from: dialogue, action, plotTwist, characterIntro, worldBuilding, quote, reflection, humor, tension, romance. " +
        "4) The single most memorable or quotable line from the transcript, verbatim, approximately 50 words max. If none stands out, use an empty string. " +
        "5) Character names mentioned or speaking. If none, use an empty array. " +
        "6) The overall mood: tense, funny, sad, romantic, inspirational, mysterious, peaceful, or dramatic."
    )

    /// Generates a moment name and note from the transcript using the on-device foundation model.
    /// - Parameters:
    ///   - transcript: The transcribed audio text
    ///   - audiobookTitle: Optional context for the model
    /// - Returns: A tuple of (name: String, note: String)
    func generateMomentName(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> (name: String, note: String) {
        let analysis = try await analyzeMoment(transcript: transcript, audiobookTitle: audiobookTitle)
        return (name: analysis.name, note: analysis.note)
    }

    /// Full analysis of an audiobook moment including categories, quote, characters, and mood.
    func analyzeMoment(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> MomentAnalysis {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw MomentNamingError.modelUnavailable
        }

        var promptText = "Analyze this audiobook excerpt:\n\n\"\(transcript)\""
        if let title = audiobookTitle, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: Prompt(promptText),
            generating: MomentNameSuggestion.self
        )

        let content = response.content
        let name = content.momentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = content.momentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let categories = content.categories.compactMap { MomentCategory(rawValue: $0) }
        let quote = content.quoteLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = content.characters.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let mood = MomentMood(rawValue: content.mood.trimmingCharacters(in: .whitespacesAndNewlines))

        return MomentAnalysis(
            name: name.isEmpty ? "Saved Moment" : name,
            note: note,
            categories: categories,
            quoteLine: quote.isEmpty ? nil : quote,
            characters: characters,
            mood: mood
        )
    }
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
