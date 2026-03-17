//
//  MomentNamingService.swift
//  Ebooker
//

import Foundation
import FoundationModels

/// Uses the foundational local model (SystemLanguageModel.default) to generate
/// a concise moment name from an audiobook transcript.
enum MomentNamingService {
    @Generable(description: "A short name for an audiobook moment bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "3–5 word phrase capturing the key concept or event from the transcript")
        var momentName: String
    }

    private static let instructions = Instructions(
        "You are an assistant that creates brief, descriptive names for audiobook bookmarks. " +
        "Given a transcript excerpt, output a concise 3–5 word phrase that captures the main topic, event, or idea. " +
        "Keep it short and memorable. Use title case."
    )

    /// Generates a moment name from the transcript using the on-device foundation model.
    /// - Parameters:
    ///   - transcript: The transcribed audio text
    ///   - audiobookTitle: Optional context for the model
    /// - Returns: A suggested moment name, or nil if generation fails
    static func generateMomentName(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw MomentNamingError.modelUnavailable
        }

        var promptText = "Create a moment name for this audiobook excerpt:\n\n\"\(transcript)\""
        if let title = audiobookTitle, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: Prompt(promptText),
            generating: MomentNameSuggestion.self
        )

        let name = response.content.momentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Saved Moment" : name
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
