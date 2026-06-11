//
//  MomentNamingService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Uses the foundational local model to generate a concise moment name and
/// analysis from an audiobook transcript.
@available(iOS 26, *)
struct MomentNamingService: MomentAnalyzing {
    /// Permissive content-transformation guardrails: this feature transforms the
    /// user's own audiobook audio, and default guardrails false-positive on fiction
    /// (violence/romance). Availability mirrors `SystemLanguageModel.default`.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// Greedy decoding — extraction tasks want determinism, not creativity.
    /// Token cap bounds worst-case latency; the schema fits comfortably under it.
    static let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 500)

    /// Single source for the @Guide literals below; unit tests assert these match
    /// `MomentCategory`/`MomentMood`. (Literals are repeated inside @Guide because
    /// macro arguments are captured expressions — keep all three places in sync.)
    static let categoryGuideValues = [
        "dialogue", "action", "plotTwist", "characterIntro", "worldBuilding",
        "quote", "reflection", "humor", "tension", "romance",
    ]
    static let moodGuideValues = [
        "tense", "funny", "sad", "romantic", "inspirational", "mysterious", "peaceful", "dramatic",
    ]

    // Field order matters: the model generates fields top-to-bottom and can run out
    // of output tokens before reaching the last one. Keep cheap, structured fields
    // first and put the longer prose (`momentNote`) at the end so a truncated tail
    // is recoverable by post-processing.
    @Generable(description: "Analysis of an audiobook moment bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "Concise 3–5 word title in Title Case, capturing the key event or idea")
        var momentName: String

        @Guide(
            description: "1–3 categories that fit the excerpt",
            .count(1...3),
            .element(.anyOf([
                "dialogue", "action", "plotTwist", "characterIntro", "worldBuilding",
                "quote", "reflection", "humor", "tension", "romance",
            ]))
        )
        var categories: [String]

        @Guide(
            description: "Overall mood of the excerpt",
            .anyOf(["tense", "funny", "sad", "romantic", "inspirational", "mysterious", "peaceful", "dramatic"])
        )
        var mood: String

        @Guide(description: "Character names speaking or mentioned. Empty array if none.", .maximumCount(6))
        var characters: [String]

        @Guide(description: "Single most memorable line copied word-for-word from the transcript, 5 to 20 words. Must be a complete sentence ending with '.', '!' or '?'. If no complete quotable sentence exists, use an empty string — never invent or paraphrase.")
        var quoteLine: String

        @Guide(description: "Exactly 2 short sentences (max 40 words total) summarizing what is happening and why it matters. Must end with a period.")
        var momentNote: String
    }

    private static let instructionPrompt: String = {
        let parts = [
            "You analyze short excerpts from audiobooks the listener is playing. ",
            "The transcript comes from automatic speech recognition: it may contain small recognition errors. ",
            "Be concise — output is constrained by a small token budget, so every field must be complete and self-contained. Produce: ",
            "1) momentName: a 3–5 word Title Case phrase capturing the key event or idea. ",
            "2) categories: 1–3 categories that fit the excerpt. ",
            "3) mood: the overall mood. ",
            "4) characters: names of people speaking or mentioned (empty array if none). ",
            "5) quoteLine: ONE complete sentence copied word-for-word from the transcript, 5–20 words, ending in '.', '!' or '?'. If no complete quotable sentence exists, return an empty string — never invent or paraphrase. ",
            "6) momentNote: exactly 2 short sentences (max 40 words total) summarizing what is happening and why it matters. Both sentences must end with a period. Never leave a sentence unfinished.",
        ]
        return parts.joined()
    }()

    private let instructions = Instructions(Self.instructionPrompt)

    /// Loads model resources before the first analyze call. The prewarmed session is
    /// consumed by exactly one analysis (sessions are multi-turn; reuse would pollute
    /// the next analysis's context).
    func prewarm() {
        let instructions = self.instructions
        Task { @MainActor in
            guard Self.model.isAvailable, PrewarmedMomentSession.session == nil else { return }
            let session = LanguageModelSession(model: Self.model, instructions: instructions)
            session.prewarm()
            PrewarmedMomentSession.session = session
        }
    }

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
        guard Self.model.isAvailable else {
            throw MomentNamingError.modelUnavailable
        }

        let instructions = self.instructions
        let content: MomentNameSuggestion
        do {
            var isFirstAttempt = true
            content = try await FoundationModelGeneration.run(transcript: transcript) { attemptTranscript in
                let session: LanguageModelSession
                if isFirstAttempt, let prewarmed = await PrewarmedMomentSession.take() {
                    session = prewarmed
                } else {
                    session = LanguageModelSession(model: Self.model, instructions: instructions)
                }
                isFirstAttempt = false

                var promptText = "Analyze this audiobook excerpt:\n\n\"\(attemptTranscript)\""
                if let title = audiobookTitle, !title.isEmpty {
                    promptText += "\n\nFrom: \(title)"
                }
                let response = try await session.respond(
                    to: Prompt(promptText),
                    generating: MomentNameSuggestion.self,
                    options: Self.options
                )
                return response.content
            }
        } catch FoundationModelGeneration.Failure.unsafeContent {
            throw MomentNamingError.unsafeContent
        } catch let error as MomentNamingError {
            throw error
        } catch {
            throw MomentNamingError.generationFailed
        }

        let trimSet = CharacterSet.whitespacesAndNewlines
        let name = content.momentName.trimmingCharacters(in: trimSet)
        let note = trimToCompleteSentences(content.momentNote)
        let categories = content.categories.compactMap { MomentCategory(rawValue: $0) }
        let quote = verifiedQuote(content.quoteLine, transcript: transcript)
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

    /// Sanitizes the model's quote, then guarantees it is verbatim from the transcript:
    /// keeps it when the transcript contains it (ignoring case/punctuation/diacritics),
    /// snaps near-misses to the best-matching transcript sentence, drops fabrications.
    func verifiedQuote(_ rawQuote: String, transcript: String) -> String {
        let sanitized = sanitizedQuoteLine(rawQuote, transcript: transcript)
        guard !sanitized.isEmpty else { return "" }
        let quoteKey = Self.matchKey(sanitized)
        guard !quoteKey.isEmpty else { return "" }

        if Self.matchKey(transcript).contains(quoteKey) {
            return sanitized
        }
        return Self.bestMatchingSentence(for: sanitized, in: transcript) ?? ""
    }

    /// Lowercased, diacritic-folded, punctuation-stripped, whitespace-collapsed form
    /// used for verbatim comparison.
    static func matchKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                result.append(sentence)
            }
        }
        return result
    }

    /// Transcript sentence sharing ≥ 70% of the quote's words; nil when the quote has
    /// fewer than 3 words or nothing in the transcript comes close.
    static func bestMatchingSentence(for quote: String, in transcript: String) -> String? {
        let quoteWords = Set(matchKey(quote).split(separator: " "))
        guard quoteWords.count >= 3 else { return nil }

        var best: (sentence: String, score: Double)?
        for sentence in sentences(in: transcript) {
            guard sentence.count >= 20, sentence.count <= 220 else { continue }
            let sentenceWords = Set(matchKey(sentence).split(separator: " "))
            guard !sentenceWords.isEmpty else { continue }
            let score = Double(quoteWords.intersection(sentenceWords).count) / Double(quoteWords.count)
            if score > (best?.score ?? 0) {
                best = (sentence, score)
            }
        }
        guard let best, best.score >= 0.7 else { return nil }
        return best.sentence
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

/// Holds at most one prewarmed session, consumed by the next analysis.
@available(iOS 26, *)
@MainActor
enum PrewarmedMomentSession {
    static var session: LanguageModelSession?

    static func take() -> LanguageModelSession? {
        defer { session = nil }
        return session
    }
}
