//
//  MomentNamingService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Uses the foundational local model (SystemLanguageModel.default) to generate
/// a concise moment name from an audiobook transcript.
struct MomentNamingService: MomentAnalyzing {
    @Generable(description: "Analysis of an audiobook bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "A 3 to 5 word title-case phrase naming this moment. No quotes, no trailing punctuation.")
        var momentName: String

        @Guide(description: "Two to four sentences explaining what is happening, what led up to it, and why it matters. 80 words max.")
        var momentNote: String

        @Guide(description: "Pick 1 to 3 values from this exact list: dialogue, action, plotTwist, characterIntro, worldBuilding, quote, reflection, humor, tension, romance.")
        var categories: [String]

        @Guide(description: "One sentence copied word-for-word from the transcript. 220 characters max. Do not paraphrase or rewrite. If nothing stands out, return an empty string.")
        var quoteLine: String

        @Guide(description: "Names of characters who speak or are named in the transcript. First names when possible. Empty list if none.")
        var characters: [String]

        @Guide(description: "One value from this exact list: tense, funny, sad, romantic, inspirational, mysterious, peaceful, dramatic.")
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

    private static let instructionPrompt: String = {
        let parts = [
            "You analyze a single bookmarked moment from an audiobook. The transcript may be short and mid-scene. ",
            "First EXTRACT from the transcript: ",
            "categories (the moment types that fit), ",
            "characters (people named or speaking, first names when possible), ",
            "mood (the overall feeling), ",
            "quoteLine (one sentence copied verbatim from the transcript, or empty if nothing stands out). ",
            "Then GENERATE: ",
            "momentName (a 3 to 5 word title-case phrase capturing the gist), ",
            "momentNote (2 to 4 sentences explaining what is happening and why it matters). ",
            "Stay inside the transcript. Do not invent characters, plot, or quotes.",
        ]
        return parts.joined()
    }()

    private let instructions = Instructions(Self.instructionPrompt)

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
        let trimSet = CharacterSet.whitespacesAndNewlines
        let name = content.momentName.trimmingCharacters(in: trimSet)
        let note = content.momentNote.trimmingCharacters(in: trimSet)
        let categories = content.categories.compactMap { MomentCategory(rawValue: $0) }
        let quote = sanitizedQuoteLine(content.quoteLine, transcript: transcript)
        let characters = content.characters.map { $0.trimmingCharacters(in: trimSet) }.filter { !$0.isEmpty }
        let mood = MomentMood(rawValue: content.mood.trimmingCharacters(in: trimSet))

        return MomentAnalysis(
            name: name.isEmpty ? "Saved Moment" : name,
            note: note,
            categories: categories,
            quoteLine: quote.isEmpty ? nil : quote,
            characters: characters,
            mood: mood
        )
    }

    /// Outer wrapping double-quote characters only — apostrophes (`'`, `\u{2018}`, `\u{2019}`)
    /// are preserved so contractions like "don't" and openings like "'Tis" stay intact.
    private static let outerWrappingQuoteChars = CharacterSet(charactersIn: "\"\u{201C}\u{201D}")

    func sanitizedQuoteLine(_ rawQuote: String, transcript: String) -> String {
        let normalized = rawQuote
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: Self.outerWrappingQuoteChars)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }

        let transcriptLength = max(transcript.count, 1)
        let maxQuoteCharacters = 220
        let transcriptRatio = Double(normalized.count) / Double(transcriptLength)

        if normalized.count > maxQuoteCharacters || transcriptRatio > 0.45 {
            let candidate = firstSentence(in: normalized, maxLength: 140)
            guard !candidate.isEmpty else { return "" }
            return candidate
        }

        return normalized
    }

    func firstSentence(in text: String, maxLength: Int) -> String {
        let punctuation = CharacterSet(charactersIn: ".!?")
        var sentence = ""

        for scalar in text.unicodeScalars {
            if sentence.count >= maxLength { break }
            sentence.unicodeScalars.append(scalar)
            if punctuation.contains(scalar) {
                break
            }
        }

        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 24 {
            return trimmed
        }

        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
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
