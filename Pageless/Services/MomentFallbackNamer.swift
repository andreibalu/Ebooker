//
//  MomentFallbackNamer.swift
//  Pageless
//

import Foundation
import NaturalLanguage

/// Names a smart-save moment without the language model, from the transcript, chapter and
/// position. Smart save uses it whenever transcription or generation fails, so the sheet
/// always opens with something more useful than "Saved Moment".
enum MomentFallbackNamer {
    /// Leaves note, quote, mood and categories empty: only the model may claim those.
    static func analysis(transcript: String?, chapterTitle: String?, time: Double) -> MomentAnalysis {
        let characters = transcript.map { personNames(in: $0) } ?? []
        let chapter = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clock = TimeFormatter.clockString(seconds: time)
        let name: String
        switch (characters.first(where: { $0.mentions >= 2 })?.name, chapter.isEmpty) {
        case let (lead?, false): name = "\(lead) in \(chapter)"
        case let (lead?, true): name = "Moment with \(lead)"
        case (nil, false): name = "\(chapter) at \(clock)"
        case (nil, true): name = "Moment at \(clock)"
        }
        return MomentAnalysis(
            name: name,
            note: "",
            categories: [],
            quoteLine: nil,
            characters: Array(characters.map(\.name).prefix(6)),
            mood: nil
        )
    }

    /// Person names, most mentioned first. The NaturalLanguage name tagger needs a language
    /// asset that is not always installed (simulators lack it), so capitalized words stand in
    /// when it finds nothing.
    static func personNames(in text: String) -> [(name: String, mentions: Int)] {
        let tagged = taggedPersonNames(in: text)
        return tagged.isEmpty ? capitalizedNames(in: text) : tagged
    }

    /// A bare surname that ends a longer name already seen ("Darcy" after "Mr. Darcy") counts
    /// toward that name.
    static func taggedPersonNames(in text: String) -> [(name: String, mentions: Int)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [String: Int] = [:]
        var order: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard tag == .personalName else { return true }
            let name = String(text[range])
            let key = order.first { $0 == name || $0.hasSuffix(" " + name) } ?? name
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
            return true
        }
        return ranked(order, counts)
    }

    /// Words capitalized at least once mid-sentence (so not just sentence starts), counted
    /// wherever they appear. Honorifics join the following name ("Mr. Darcy").
    static func capitalizedNames(in text: String) -> [(name: String, mentions: Int)] {
        let honorifics: Set<String> = ["Mr", "Mrs", "Ms", "Miss", "Dr", "Sir", "Lady", "Lord", "Captain", "Madame", "Monsieur"]
        let common: Set<String> = [
            "I", "The", "A", "An", "And", "But", "Or", "It", "He", "She", "They", "We", "You", "His", "Her",
            "Their", "My", "Our", "Your", "This", "That", "There", "Then", "When", "What", "Who", "Why", "How",
            "Yes", "No", "Oh", "Well", "God", "Heaven", "Chapter", "Book", "Part",
        ]
        var counts: [String: Int] = [:]
        var order: [String] = []
        var properNouns = Set<String>()
        var sentenceStart = true
        var pendingHonorific: String?
        for token in text.split(whereSeparator: \.isWhitespace) {
            let word = token.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            let startsUpper = word.first?.isUppercase == true && word.count > 1
            if startsUpper, honorifics.contains(word) {
                pendingHonorific = word
            } else if startsUpper, !common.contains(word) {
                let name = pendingHonorific.map { "\($0). \(word)" } ?? word
                let key = order.first { $0 == name || $0.hasSuffix(" " + name) } ?? name
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
                if !sentenceStart || pendingHonorific != nil { properNouns.insert(key) }
                pendingHonorific = nil
            } else {
                pendingHonorific = nil
            }
            sentenceStart = token.last.map { ".!?".contains($0) } ?? false
                || token.hasSuffix(".\"") || token.hasSuffix("?\"") || token.hasSuffix("!\"")
                || token.hasSuffix(".”") || token.hasSuffix("?”") || token.hasSuffix("!”")
        }
        return ranked(order.filter(properNouns.contains), counts)
    }

    private static func ranked(_ order: [String], _ counts: [String: Int]) -> [(name: String, mentions: Int)] {
        order
            .enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map { (name: $0.element, mentions: counts[$0.element]!) }
    }
}
