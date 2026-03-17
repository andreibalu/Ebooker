//
//  MomentNamingService.swift
//  Ebooker
//

import Foundation
import FoundationModels

/// Uses the foundational local model (SystemLanguageModel.default) to generate
/// a concise moment name from an audiobook transcript.
enum MomentNamingService {
    @Generable(description: "A name and contextual note for an audiobook moment bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "3–5 word phrase capturing the key concept or event from the transcript")
        var momentName: String

        @Guide(description: "3–4 sentence description providing detailed context about what is happening at this point in the audiobook, what led to it, and why it matters")
        var momentNote: String
    }

    private static let instructions = Instructions(
        "You are an assistant that creates brief, descriptive names and detailed contextual notes for audiobook bookmarks. " +
        "Given a transcript excerpt (with context from before and after), output a concise 3–5 word title-case phrase as the name, " +
        "and 3–4 sentences as a comprehensive note. The note should describe what is happening at the central moment, " +
        "what led up to it, and why it matters. Keep the name short and memorable. The note should provide rich context " +
        "for when the listener returns later and wants to remember the full situation."
    )

    /// Generates a moment name and note from the transcript using the on-device foundation model.
    /// - Parameters:
    ///   - transcript: The transcribed audio text
    ///   - audiobookTitle: Optional context for the model
    /// - Returns: A tuple of (name: String, note: String)
    static func generateMomentName(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> (name: String, note: String) {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw MomentNamingError.modelUnavailable
        }

        var promptText = "Create a moment name and note for this audiobook excerpt:\n\n\"\(transcript)\""
        if let title = audiobookTitle, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: Prompt(promptText),
            generating: MomentNameSuggestion.self
        )

        let name = response.content.momentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = response.content.momentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            name: name.isEmpty ? "Saved Moment" : name,
            note: note
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
