//
//  MomentNamingService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Uses the foundational local model (SystemLanguageModel.default) to generate
/// a concise moment name from an audiobook transcript.
struct MomentNamingService: MomentAnalyzing {
    // Field order matters: the model generates fields top-to-bottom and can run out
    // of output tokens before reaching the last one. Keep cheap, structured fields
    // first and put the longer prose (`momentNote`) at the end so a truncated tail
    // is recoverable by post-processing.
    @Generable(description: "Analysis of an audiobook moment bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "Concise 3–5 word title in Title Case, capturing the key event or idea")
        var momentName: String

        @Guide(description: "1–3 categories from: dialogue, action, plotTwist, characterIntro, worldBuilding, quote, reflection, humor, tension, romance")
        var categories: [String]

        @Guide(description: "Overall mood, exactly one of: tense, funny, sad, romantic, inspirational, mysterious, peaceful, dramatic")
        var mood: String

        @Guide(description: "Character names speaking or mentioned. Empty array if none.")
        var characters: [String]

        @Guide(description: "Single most memorable line from the transcript, copied verbatim, 5 to 20 words. Must be a complete sentence ending with '.', '!' or '?'. If no complete quotable sentence exists, use an empty string.")
        var quoteLine: String

        @Guide(description: "Exactly 2 short sentences (max 40 words total) summarizing what is happening and why it matters. Must end with a period.")
        var momentNote: String
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
            "You analyze short audiobook bookmarks. Be concise — output is constrained by a small token budget, so every field must be complete and self-contained. Produce: ",
            "1) momentName: a 3–5 word Title Case phrase. ",
            "2) categories: 1–3 from dialogue, action, plotTwist, characterIntro, worldBuilding, quote, reflection, humor, tension, romance. ",
            "3) mood: exactly one of tense, funny, sad, romantic, inspirational, mysterious, peaceful, dramatic. ",
            "4) characters: names of people speaking or mentioned (empty array if none). ",
            "5) quoteLine: ONE complete sentence copied verbatim from the transcript, 5–20 words, ending in '.', '!' or '?'. If no complete quotable sentence exists, return an empty string — never return a partial sentence. ",
            "6) momentNote: exactly 2 short sentences (max 40 words total) summarizing what is happening and why it matters. Both sentences must end with a period. Never leave a sentence unfinished.",
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
        let note = trimToCompleteSentences(content.momentNote)
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

    func sanitizedQuoteLine(_ rawQuote: String, transcript: String) -> String {
        let normalized = rawQuote
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"“”'")))

        guard !normalized.isEmpty else { return "" }

        let transcriptLength = max(transcript.count, 1)
        let maxQuoteCharacters = 220
        let transcriptRatio = Double(normalized.count) / Double(transcriptLength)

        // If the model returns something transcript-sized, treat it as invalid and
        // only keep the first complete sentence — never a prefix that ends mid-word.
        if normalized.count > maxQuoteCharacters || transcriptRatio > 0.45 {
            let candidate = firstSentence(in: normalized, maxLength: 140)
            if let last = candidate.last, ".!?".contains(last), candidate.count >= 20 {
                return candidate
            }
            return ""
        }

        // The model can run out of output tokens mid-word. Only accept quotes that
        // end with terminal punctuation; otherwise trim back to the last complete
        // sentence, or drop the quote entirely if no complete sentence remains.
        if let last = normalized.last, ".!?".contains(last) {
            return normalized
        }
        return lastCompleteSentence(in: normalized, minLength: 20)
    }

    /// Returns the input trimmed back to its last terminal-punctuation boundary.
    /// Used to repair model output truncated mid-sentence by the token cap.
    func trimToCompleteSentences(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }
        let recovered = lastCompleteSentence(in: trimmed, minLength: 20)
        if !recovered.isEmpty { return recovered }
        // No complete sentence found — append an ellipsis so the user sees the
        // text is intentional rather than mid-word truncation.
        return trimmed + "…"
    }

    /// Returns the prefix of `text` ending at its final '.', '!' or '?', or an
    /// empty string if no terminator exists or the result would be shorter than
    /// `minLength` characters.
    func lastCompleteSentence(in text: String, minLength: Int) -> String {
        let terminators: Set<Character> = [".", "!", "?"]
        guard let idx = text.lastIndex(where: { terminators.contains($0) }) else {
            return ""
        }
        let prefix = String(text[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.count >= minLength ? prefix : ""
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
