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
    /// when it finds no person. Places and organizations the tagger did find stay out of them.
    static func personNames(in text: String) -> [(name: String, mentions: Int)] {
        let tagged = taggedNames(in: text)
        return tagged.people.isEmpty ? capitalizedNames(in: text, excluding: tagged.otherNames) : tagged.people
    }

    /// People ranked by mentions, plus every word of the place and organization names. A bare
    /// surname that ends a longer name already seen ("Darcy" after "Mr. Darcy") counts toward
    /// that name.
    static func taggedNames(in text: String) -> (people: [(name: String, mentions: Int)], otherNames: Set<String>) {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [String: Int] = [:]
        var order: [String] = []
        var otherNames = Set<String>()
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let name = String(text[range])
            switch tag {
            case .personalName?:
                let key = order.first { $0 == name || $0.hasSuffix(" " + name) } ?? name
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
            case .placeName?, .organizationName?:
                otherNames.formUnion(name.split(separator: " ").map(String.init))
            default:
                break
            }
            return true
        }
        return (ranked(order, counts), otherNames)
    }

    /// Words capitalized at least once mid-sentence (so not just sentence starts), counted
    /// wherever they appear. Honorifics join the following name ("Mr. Darcy"), and a possessive
    /// counts toward its name. Days, months and words that look like places once ("in London",
    /// "Baker Street") are dropped everywhere, as is anything in `excluding`.
    static func capitalizedNames(in text: String, excluding: Set<String> = []) -> [(name: String, mentions: Int)] {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let words = tokens.map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
        var counts: [String: Int] = [:]
        var order: [String] = []
        var properNouns = Set<String>()
        var places = excluding
        var sentenceStart = true
        var pendingHonorific: String?
        for (index, token) in tokens.enumerated() {
            var word = words[index]
            let isPossessive = word.hasSuffix("'s") || word.hasSuffix("’s")
            if isPossessive { word.removeLast(2) }
            // "I'm", "I'll" and "I've" are capitalized mid-sentence too, and lead first-person passages.
            let isFirstPerson = word.hasPrefix("I'") || word.hasPrefix("I’")
            let startsUpper = word.first?.isUppercase == true && word.count > 1 && !isFirstPerson
            if startsUpper, honorifics.contains(word) {
                pendingHonorific = word
            } else if startsUpper, !common.contains(word), !calendarWords.contains(word), !placeNouns.contains(word) {
                let name = pendingHonorific.map { "\($0). \(word)" } ?? word
                let key = order.first { $0 == name || $0.hasSuffix(" " + name) } ?? name
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
                if !sentenceStart || pendingHonorific != nil { properNouns.insert(key) }
                let followsPlacePreposition = index > 0
                    && placePrepositions.contains(words[index - 1].lowercased())
                    && tokens[index - 1].last?.isLetter == true
                let precedesPlaceNoun = words.indices.contains(index + 1) && placeNouns.contains(words[index + 1])
                if pendingHonorific == nil, (followsPlacePreposition && !isPossessive) || precedesPlaceNoun {
                    places.insert(key)
                }
                pendingHonorific = nil
            } else {
                pendingHonorific = nil
            }
            sentenceStart = token.last.map { ".!?".contains($0) } ?? false
                || token.hasSuffix(".\"") || token.hasSuffix("?\"") || token.hasSuffix("!\"")
                || token.hasSuffix(".”") || token.hasSuffix("?”") || token.hasSuffix("!”")
        }
        return ranked(order.filter { properNouns.contains($0) && !places.contains($0) }, counts)
    }

    private static let honorifics: Set<String> = [
        "Mr", "Mrs", "Ms", "Miss", "Dr", "Sir", "Lady", "Lord", "Captain", "Madame", "Monsieur",
    ]
    private static let common: Set<String> = [
        "I", "The", "A", "An", "And", "But", "Or", "It", "He", "She", "They", "We", "You", "His", "Her",
        "Their", "My", "Our", "Your", "This", "That", "There", "Then", "When", "What", "Who", "Why", "How",
        "Yes", "No", "Oh", "Well", "God", "Heaven", "Chapter", "Book", "Part",
    ]
    private static let calendarWords: Set<String> = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "January", "February", "March", "April", "May", "June", "July", "August", "September",
        "October", "November", "December", "Christmas", "Easter",
    ]
    /// "in Elizabeth" is rare; "in London" is how a passage names a place. "at" and "to" are left
    /// out because "looked at Jane" and "said to Jane" are common.
    private static let placePrepositions: Set<String> = ["in", "into", "near", "inside", "across", "toward", "towards"]
    private static let placeNouns: Set<String> = [
        "Street", "Square", "Road", "Lane", "Avenue", "Place", "Court", "Hall", "House", "Park", "Abbey",
        "Castle", "Manor", "Church", "Cathedral", "Bridge", "Station", "River", "Hill", "Island", "Bay",
    ]

    private static func ranked(_ order: [String], _ counts: [String: Int]) -> [(name: String, mentions: Int)] {
        order
            .enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map { (name: $0.element, mentions: counts[$0.element]!) }
    }
}
