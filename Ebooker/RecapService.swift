//
//  RecapService.swift
//  Ebooker
//

import Foundation
import FoundationModels

/// Uses the on-device foundation model to generate a brief recap of recent audiobook events.
enum RecapService {
    @Generable(description: "A brief recap of recent audiobook events")
    struct RecapSuggestion {
        @Guide(description: "2-sentence summary of what happened recently in the audiobook")
        var recap: String
    }

    private static let instructions = Instructions(
        "You are an assistant that helps audiobook listeners remember where they left off. " +
        "Given a transcript of the most recent audio, write a 2-sentence summary of what just happened. " +
        "Focus on key events, character actions, and plot developments. Be concise and spoiler-aware."
    )

    /// Generates a recap from a transcript of recent audio.
    /// - Parameters:
    ///   - transcript: Transcribed audio text from the recent listening segment
    ///   - audiobookTitle: Optional book title for context
    /// - Returns: A 2-sentence recap string
    static func generateRecap(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw RecapError.modelUnavailable
        }

        var promptText = "Summarize what just happened in this audiobook excerpt:\n\n\"\(transcript)\""
        if let title = audiobookTitle, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: Prompt(promptText),
            generating: RecapSuggestion.self
        )

        return response.content.recap.trimmingCharacters(in: .whitespacesAndNewlines)
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
