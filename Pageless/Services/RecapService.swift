//
//  RecapService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Uses the on-device foundation model to generate a brief recap of recent audiobook events.
struct RecapService: RecapProviding {
    @Generable(description: "A brief recap of recent audiobook events")
    struct RecapSuggestion {
        @Guide(description: "2-sentence summary of what happened recently in the audiobook")
        var recap: String
    }

    @Generable(description: "Recap plus a one-line headline for the progress row")
    struct RecapWithHeadlineSuggestion {
        @Guide(description: "2-sentence summary of what happened recently in the audiobook")
        var recap: String
        @Guide(description: "Exactly 3 to 4 words summarizing where the listener left off, for a single UI line. No punctuation at the end.")
        var progressHeadline: String
    }

    @Generable(description: "A welcome-back recap to help a listener resume an audiobook after a break")
    struct ComebackRecapSuggestion {
        @Guide(description: "Where the scene takes place. One short phrase, 3 to 8 words. If unclear from the excerpt, write 'unknown'.")
        var location: String
        @Guide(description: "Names of characters who appear in this excerpt. Up to 4 names. First names when possible. Empty list if nobody is named.")
        var characters: [String]
        @Guide(description: "Two short sentences (max 45 words) summarizing what just happened. Lead with the most recent event. Stay strictly inside the excerpt.")
        var summary: String
    }

    private let instructions = Instructions(
        "You are an assistant that helps audiobook listeners remember where they left off. " +
        "Given a transcript of the most recent audio, write a 2-sentence summary of what just happened. " +
        "Focus on key events, character actions, and plot developments. Be concise and spoiler-aware."
    )

    private let instructionsWithHeadline = Instructions(
        "You are an assistant that helps audiobook listeners remember where they left off. " +
        "Given a transcript of the most recent audio, write a 2-sentence summary of what just happened. " +
        "Also provide progressHeadline: exactly 3 to 4 words that capture the gist for a single-line UI label (no ending punctuation). " +
        "Focus on key events and be spoiler-aware."
    )

    private let comebackInstructions = Instructions(
        "You are helping an audiobook listener pick up after a few hours away. Given a transcript of the last few minutes of audio, do three things. " +
        "First: LOCATION — name the place the scene happens in, in a single short phrase (3 to 8 words). If the excerpt does not make the location clear, return \"unknown\". " +
        "Second: CHARACTERS — list up to four people who appear in this excerpt by name. Use first names when possible. Return an empty list if nobody is named. " +
        "Third: SUMMARY — write two sentences (max 45 words) recapping what just happened. Lead with the most recent moment. " +
        "Stay strictly inside the excerpt. Do not invent or predict anything outside it."
    )

    /// Generates a recap from a transcript of recent audio.
    func generateRecap(
        transcript: String,
        audiobookTitle: String? = nil,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw RecapError.modelUnavailable
        }

        var promptText = "Summarize what just happened in this audiobook excerpt:\n\n\"\(transcript)\""
        if let title = audiobookTitle, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }

        if includeProgressHeadline {
            let session = LanguageModelSession(model: model, instructions: instructionsWithHeadline)
            let response = try await session.respond(
                to: Prompt(promptText),
                generating: RecapWithHeadlineSuggestion.self
            )
            let recap = response.content.recap.trimmingCharacters(in: .whitespacesAndNewlines)
            let headline = Self.sanitizeHeadline(response.content.progressHeadline)
            return RecapGenerationResult(recap: recap, progressHeadline: headline)
        } else {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: Prompt(promptText),
                generating: RecapSuggestion.self
            )
            let recap = response.content.recap.trimmingCharacters(in: .whitespacesAndNewlines)
            return RecapGenerationResult(recap: recap, progressHeadline: nil)
        }
    }

    /// Keeps at most four words for a single-line UI label.
    static func sanitizeHeadline(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return trimmed }
        return words.prefix(4).joined(separator: " ")
    }

    func generateComebackRecap(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> ComebackRecapResult {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw RecapError.modelUnavailable
        }

        var promptText = "Recap the last few minutes of this audiobook so the listener can pick up where they left off:\n\n\"\(transcript)\""
        if let title = audiobookTitle, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }

        let session = LanguageModelSession(model: model, instructions: comebackInstructions)
        let response = try await session.respond(
            to: Prompt(promptText),
            generating: ComebackRecapSuggestion.self
        )

        return Self.sanitizeComeback(
            rawLocation: response.content.location,
            rawCharacters: response.content.characters,
            rawSummary: response.content.summary
        )
    }

    /// Pure helper for tests: normalizes location, clamps characters, truncates summary.
    static func sanitizeComeback(
        rawLocation: String,
        rawCharacters: [String],
        rawSummary: String
    ) -> ComebackRecapResult {
        let trimmedLocation = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = trimmedLocation.lowercased() == "unknown" ? "" : trimmedLocation

        let characters = rawCharacters
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)

        var summary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.count > 350 {
            summary = String(summary.prefix(350)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ComebackRecapResult(
            location: location,
            characters: Array(characters),
            summary: summary
        )
    }
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
