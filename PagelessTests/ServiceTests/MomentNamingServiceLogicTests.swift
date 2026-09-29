//
//  MomentNamingServiceLogicTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct MomentNamingServiceLogicTests {

    // MARK: - sanitizedQuoteLine

    @Test func sanitizedQuoteStripsQuoteMarksAndCollapsesNewlines() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = String(repeating: "x", count: 50)
        #expect(service.sanitizedQuoteLine("\"“”'Hello there.'”\"", transcript: transcript) == "Hello there.")
        #expect(service.sanitizedQuoteLine("Line one\nLine two\r\nLine three.", transcript: transcript) == "Line one Line two Line three.")
        #expect(service.sanitizedQuoteLine("", transcript: "anything").isEmpty)
    }

    @Test func sanitizedQuoteDropsQuotesWithoutAUsableCompleteSentence() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        // The model ran out of output tokens mid-word — no terminal punctuation,
        // no recoverable complete sentence. Drop the quote rather than show a partial.
        #expect(service.sanitizedQuoteLine(
            "I cannot describe to you my sensations on the near prospect of my undertaking it is impossible to communicate to you a conception of the tre",
            transcript: String(repeating: "x", count: 500)
        ).isEmpty)
        // Overlong with no terminator — there is no safe sentence to extract.
        #expect(service.sanitizedQuoteLine(
            String(repeating: "z", count: 230),
            transcript: String(repeating: "a", count: 1_000)
        ).isEmpty)
        // High ratio triggers the overlong branch; "Hi." is too short to be a usable
        // quote (< 20 chars after trim), and the rest has no terminator.
        #expect(service.sanitizedQuoteLine("Hi." + String(repeating: "x", count: 220), transcript: "ab").isEmpty)
    }

    @Test func sanitizedQuoteKeepsOnlyCompleteSentences() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        #expect(service.sanitizedQuoteLine(
            "She closed the door behind her. He followed without a word, but his hand trem",
            transcript: String(repeating: "x", count: 500)
        ) == "She closed the door behind her.")

        let firstSentence = "She walked into the storm without looking back."
        #expect(service.sanitizedQuoteLine(
            firstSentence + " " + String(repeating: "x", count: 230),
            transcript: String(repeating: "a", count: 1_000)
        ) == firstSentence)
    }

    // MARK: - firstSentence

    @Test func firstSentenceTruncatesToMaxLengthWhenNoTerminator() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let text = "abcdefghijklmnopqrstuvwxyz"
        let out = service.firstSentence(in: text, maxLength: 10)
        #expect(out == "abcdefghij")
    }

    // MARK: - trimToCompleteSentences

    @Test func trimNoteKeepsWholeSentencesAndEllipsizesFragments() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let complete = "Victor decides to embark on a perilous voyage. The moment marks a turning point in his life."
        #expect(service.trimToCompleteSentences(complete) == complete)

        // Mirrors the truncation seen on-device when the model exhausts its output budget
        // mid-sentence after generating the longer second sentence.
        let truncated = "Victor decides to embark on a perilous voyage. This moment is pivotal as it marks a significant turning point in his life, highlighting the tension between personal"
        #expect(service.trimToCompleteSentences(truncated) == "Victor decides to embark on a perilous voyage.")

        let fragment = service.trimToCompleteSentences("Victor decides to embark on a perilous voyage and")
        #expect(fragment.hasSuffix("…"))
        #expect(!fragment.contains("..."))

        #expect(service.trimToCompleteSentences("").isEmpty)
        #expect(service.trimToCompleteSentences("   \n  ").isEmpty)
    }

    // MARK: - verifiedQuote

    @Test func verifiedQuoteKeepsVerbatimQuoteAndSnapsParaphrase() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
        let sentence = "The storm broke over the harbor at midnight, and nobody slept."
        #expect(service.verifiedQuote(sentence, transcript: transcript) == sentence)
        // Model dropped words — most of the words still come from one transcript sentence.
        #expect(service.verifiedQuote("Storm broke over harbor at midnight, nobody slept!", transcript: transcript) == sentence)
    }

    @Test func verifiedQuoteDropsFabricatedAndShortNonVerbatimQuotes() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
        #expect(service.verifiedQuote("To be or not to be, that is the question.", transcript: transcript).isEmpty)
        #expect(service.verifiedQuote("Harbor explosions!", transcript: transcript).isEmpty)
    }

    // MARK: - matchKey / sentences

    @Test func matchKeyFoldsCasePunctuationAndDiacritics() {
        guard #available(iOS 26, *) else { return }
        #expect(MomentNamingService.matchKey("Café—NIGHT, falls!") == "cafe night falls")
    }

    @Test func sentencesSplitsOnTerminators() {
        guard #available(iOS 26, *) else { return }
        let out = MomentNamingService.sentences(in: "One came first. Two came second! Three came third?")
        #expect(out == ["One came first.", "Two came second!", "Three came third?"])
    }

    // MARK: - Guide value sync (guards MomentEnums drift against the @Guide literals)

    @Test func guideValuesMatchEnums() {
        guard #available(iOS 26, *) else { return }
        #expect(MomentNamingService.categoryGuideValues == MomentCategory.allCases.map(\.rawValue))
        #expect(MomentNamingService.moodGuideValues == MomentMood.allCases.map(\.rawValue))
    }
}
