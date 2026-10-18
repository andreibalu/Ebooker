//
//  MomentAnalysisParser.swift
//  Pageless
//

import Foundation

/// Turns the model's labeled-line reply into a `MomentAnalysis`, and holds the reply format
/// the prompt asks for so the two can't drift apart. Foundation only: tests and older-iOS
/// builds use it without gating.
enum MomentAnalysisParser {
    static let labels = ["Title", "Note", "Mood", "Categories", "Characters", "Quote"]

    /// The reply format, written into the instructions. The mood and category vocabularies
    /// come from the enums, so a new case reaches the prompt and the parser together.
    ///
    /// Measured on the on-device model: writing the note before the tags makes it describe the
    /// passage first, which spreads the categories out; and the small model copies list order,
    /// so the category choices are alphabetical rather than led by "action, plot twist".
    static var replyFormat: String {
        let moods = MomentMood.allCases.map(\.rawValue).joined(separator: ", ")
        let categories = MomentCategory.allCases.map { $0.displayName.lowercased() }.sorted().joined(separator: ", ")
        return """
        Title: a 2 to 5 word title in Title Case naming the key event or idea
        Note: two short sentences on what happens and why it matters
        Mood: one of \(moods)
        Categories: the one or two that fit best, from \(categories)
        Characters: proper names of characters who speak or are mentioned, separated by commas, or none
        Quote: one complete, memorable sentence copied word for word from the passage, or none
        """
    }

    /// Nil when the reply is a refusal or carries no usable title.
    static func parse(_ reply: String, transcript: String) -> MomentAnalysis? {
        guard !AIResponseText.isRefusal(reply) else { return nil }
        let fields = AIResponseText.labeledFields(in: reply, labels: labels, overflowLabel: "Note")
        let name = AIResponseText.cleanTitle(fields["title"] ?? "")
        guard !name.isEmpty, !AIResponseText.isRefusal(name) else { return nil }

        let note = AIResponseText.isPlaceholder(fields["note"] ?? "")
            ? ""
            : AIResponseText.trimToCompleteSentences(fields["note"] ?? "")
        let quote = AIResponseText.isPlaceholder(fields["quote"] ?? "")
            ? ""
            : verifiedQuote(fields["quote"] ?? "", transcript: transcript)
        var categories: [MomentCategory] = []
        for value in AIResponseText.list(fields["categories"] ?? "") {
            if let category = category(named: value), !categories.contains(category) {
                categories.append(category)
            }
        }
        return MomentAnalysis(
            name: name,
            note: AIResponseText.isRefusal(note) ? "" : note,
            categories: Array(categories.prefix(3)),
            quoteLine: quote.isEmpty ? nil : quote,
            characters: Array(characters(in: fields["characters"] ?? "").prefix(6)),
            mood: mood(named: fields["mood"] ?? "")
        )
    }

    // MARK: - Vocabulary

    /// Proper names only: the model also lists roles ("the woman", "monster"), which make
    /// poor filter chips.
    static func characters(in value: String) -> [String] {
        AIResponseText.list(value).filter { $0.first?.isUppercase == true && !$0.hasPrefix("The ") }
    }

    /// The prompt lists display names ("plot twist"); the model may answer "plotTwist" or
    /// "Plot-Twist". All fold to the same key.
    static func category(named value: String) -> MomentCategory? {
        let key = matchKey(value).replacingOccurrences(of: " ", with: "")
        return MomentCategory.allCases.first { $0.rawValue.lowercased() == key }
    }

    static func mood(named value: String) -> MomentMood? {
        let key = matchKey(value)
        return MomentMood.allCases.first { key == $0.rawValue || key.hasPrefix($0.rawValue + " ") }
    }

    // MARK: - Quotes

    static func sanitizedQuoteLine(_ rawQuote: String, transcript: String) -> String {
        let normalized = rawQuote
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
        return AIResponseText.lastCompleteSentence(in: normalized, minLength: 20)
    }

    /// Sanitizes the model's quote, then guarantees it is verbatim from the transcript:
    /// keeps it when the transcript contains it (ignoring case/punctuation/diacritics),
    /// snaps near-misses to the best-matching transcript sentence, drops fabrications.
    static func verifiedQuote(_ rawQuote: String, transcript: String) -> String {
        let sanitized = sanitizedQuoteLine(rawQuote, transcript: transcript)
        guard !sanitized.isEmpty else { return "" }
        let quoteKey = matchKey(sanitized)
        guard !quoteKey.isEmpty else { return "" }

        if matchKey(transcript).contains(quoteKey) {
            return sanitized
        }
        return bestMatchingSentence(for: sanitized, in: transcript) ?? ""
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

    static func firstSentence(in text: String, maxLength: Int) -> String {
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
