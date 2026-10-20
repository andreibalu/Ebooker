//
//  AIResponseText.swift
//  Pageless
//

import Foundation

/// Text handling shared by the on-device AI services: tidying a speech transcript before it
/// goes into a prompt, reading the labeled-line replies the model writes, spotting refusals and
/// repairing prose the token cap clipped. Foundation only, so it builds on every iOS version.
nonisolated enum AIResponseText {
    // MARK: - Transcripts

    /// Collapses whitespace and drops a leading fragment: a window that starts mid-sentence
    /// opens on a lowercase word. The fragment confuses names and quotes and costs tokens. It is
    /// dropped only when a complete sentence follows within the first third of the text.
    static func cleanTranscript(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let first = collapsed.first, first.isLowercase else { return collapsed }
        let limit = collapsed.index(collapsed.startIndex, offsetBy: collapsed.count / 3)
        guard let boundary = collapsed[..<limit].indices.first(where: { isSentenceEnd(at: $0, in: collapsed) }) else {
            return collapsed
        }
        let rest = collapsed[collapsed.index(after: boundary)...]
            .drop(while: { $0.isWhitespace || "\"”’)".contains($0) })
        return rest.isEmpty ? collapsed : String(rest)
    }

    /// A '.', '!' or '?' followed by a space or closing quote, and not the point of an
    /// abbreviation ("Mr. Darcy") or a number ("3.5 miles").
    private static func isSentenceEnd(at index: String.Index, in text: String) -> Bool {
        guard ".!?".contains(text[index]) else { return false }
        let next = text.index(after: index)
        guard next < text.endIndex, text[next].isWhitespace || "\"”’)".contains(text[next]) else { return false }
        let word = text[..<index].split(separator: " ").last.map { $0.lowercased() } ?? ""
        return !abbreviations.contains(word)
    }

    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "sr", "jr", "prof", "mt", "vs"]

    // MARK: - Labeled replies

    /// Reads `Label: value` lines. Labels match case-insensitively and may carry markdown
    /// emphasis, bullets or numbering. Keys in the result are lowercased labels.
    ///
    /// The model writes each value on one line, but often drops the label of a closing prose
    /// field. So a line without a label goes to `overflowLabel` when one is given (unless that
    /// field was already written with its own label and has ended); otherwise it continues
    /// the previous value.
    static func labeledFields(in text: String, labels: [String], overflowLabel: String? = nil) -> [String: String] {
        let known = Set(labels.map { $0.lowercased() })
        let overflow = overflowLabel?.lowercased()
        var fields: [String: String] = [:]
        var current: String?
        func append(_ line: String, to label: String) {
            let previous = fields[label] ?? ""
            fields[label] = previous.isEmpty ? line : previous + " " + line
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let (label, value) = splitLabel(line), known.contains(label) {
                fields[label] = value
                current = label
            } else if let label = splitLabel(line)?.label, label.split(separator: " ").count <= 2 {
                // A label the reply invented ("Rating:") ends the previous value.
                current = nil
            } else if line.hasSuffix(":") {
                // A header or preamble ("Here is the analysis:") is never a value, and must not
                // claim the overflow field: unlabeled prose after it would join the title.
                current = nil
            } else if let overflow, current == overflow || fields[overflow] == nil {
                append(line, to: overflow)
                current = overflow
            } else if let current {
                append(line, to: current)
            }
        }
        return fields
    }

    private static func splitLabel(_ line: String) -> (label: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        // Bullets and numbering come off the front only, so "At 10:30" never reads as a label.
        let label = String(line[..<colon].drop(while: { "*_#-•>0123456789. ".contains($0) }))
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
            .lowercased()
        guard !label.isEmpty, label.count <= 24, label.allSatisfy({ $0.isLetter || $0 == " " }) else { return nil }
        // Only markdown emphasis comes off the value: its own punctuation is content.
        let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
        return (label, value)
    }

    /// Splits a comma or "and" separated list. Placeholders ("none", "N/A") mean empty;
    /// duplicates are dropped case-insensitively, keeping the first spelling.
    static func list(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .replacingOccurrences(of: " and ", with: ",")
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "*.\"“”"))) }
            .filter { !$0.isEmpty && !isPlaceholder($0) && seen.insert($0.lowercased()).inserted }
    }

    static func isPlaceholder(_ value: String) -> Bool {
        ["none", "n/a", "na", "unknown", "nobody", "no one", "not applicable", "-", "—"]
            .contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Strips quotes, markdown and trailing punctuation, and keeps at most `maxWords` words.
    /// The model often overshoots a word count. A plain cut ends mid-phrase ("Bingley's arrival
    /// and Jane's", "Jane and Elizabeth near"), so an over-long title is cut just before the last
    /// joiner that fits ("Bingley's arrival", "Jane and Elizabeth"). A joiner or article still
    /// left at the end goes too.
    static func cleanTitle(_ raw: String, maxWords: Int = 7) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"“”'‘’*_#")))
        guard !isPlaceholder(trimmed) else { return "" }
        let all = trimmed.split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:—–-")) }
            .filter { !$0.isEmpty }
        var words = all
        if all.count > maxWords {
            let cut = (1...maxWords).last { phraseJoiners.contains(all[$0].lowercased()) } ?? maxWords
            words = Array(all.prefix(cut))
        }
        while words.count > 1, let last = words.last, danglingWords.contains(last.lowercased()) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// Words that open a new phrase, so a title cut just before one still reads whole.
    private static let phraseJoiners: Set<String> = [
        "and", "or", "but", "nor", "&", "with", "without", "near", "at", "in", "on", "to", "from",
        "for", "of", "by", "about", "as", "into", "onto", "upon", "after", "before", "while", "during",
        "under", "over", "through", "toward", "towards", "against", "between", "beside", "behind",
        "among", "across", "beyond", "within", "than", "that", "which", "who", "where", "when",
    ]

    /// Words a title can't end on.
    private static let danglingWords: Set<String> = phraseJoiners.union([
        "a", "an", "the", "her", "his", "their", "its", "my", "our", "your",
    ])

    // MARK: - Refusals

    /// Permissive guardrails never throw for text output, but the model can still answer with a
    /// refusal sentence. That text must never become a name or a recap.
    static func isRefusal(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).lowercased()
            .replacingOccurrences(of: "’", with: "'")
        let openers = [
            "i'm sorry", "i am sorry", "sorry, but", "sorry, i", "i apologize", "i can't", "i cannot",
            "i'm unable", "i am unable", "i won't", "i will not", "as an ai", "i'm not able", "i am not able",
            "i'm afraid i", "i am afraid i", "unfortunately, i", "i must decline",
        ]
        return openers.contains { head.hasPrefix($0) }
    }

    /// A title or headline that is really a refusal. Stricter than `isRefusal`, because fiction
    /// titles open the same way ("I Won't Go Back", "I Cannot Forgive Him"): the text must also
    /// use a refusal's wording.
    static func isRefusalTitle(_ text: String) -> Bool {
        guard isRefusal(text) else { return false }
        let lower = text.lowercased()
        return ["sorry", "apolog", "as an ai", "help with", "assist", "comply", "provide"].contains { lower.contains($0) }
    }

    // MARK: - Prose repair

    /// The model sometimes starts a sentence or label in lowercase, echoing a transcript that
    /// opened mid-sentence ("the creator confronts the monster").
    static func capitalizingFirstLetter(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The token cap can stop prose mid-sentence. Trims back to the last complete sentence, or
    /// ends with an ellipsis when no complete sentence is long enough to keep.
    static func trimToCompleteSentences(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, ".!?\"”".contains(last) {
            return trimmed
        }
        let recovered = lastCompleteSentence(in: trimmed, minLength: 20)
        return recovered.isEmpty ? trimmed + "…" : recovered
    }

    /// The prefix of `text` ending at its final '.', '!' or '?', or empty when there is none or
    /// it would be shorter than `minLength` characters.
    static func lastCompleteSentence(in text: String, minLength: Int) -> String {
        guard let index = text.lastIndex(where: { ".!?".contains($0) }) else { return "" }
        let prefix = String(text[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.count >= minLength ? prefix : ""
    }
}
