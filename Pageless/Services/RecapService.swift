//
//  RecapService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Uses the on-device foundation model to generate a brief recap of recent audiobook events.
@available(iOS 26, *)
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
}
