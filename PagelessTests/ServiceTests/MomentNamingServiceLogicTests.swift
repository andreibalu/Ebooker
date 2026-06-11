//
//  MomentNamingServiceLogicTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct MomentNamingServiceLogicTests {

    // MARK: - sanitizedQuoteLine

    @Test func sanitizedQuotePassesThroughNormalQuote() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = String(repeating: "word ", count: 30)
        let out = service.sanitizedQuoteLine("A memorable line from the story.", transcript: transcript)
        #expect(out == "A memorable line from the story.")
    }

    @Test func sanitizedQuoteStripsLeadingTrailingQuoteChars() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = String(repeating: "x", count: 50)
        let out = service.sanitizedQuoteLine("\"“”'Hello there.'”\"", transcript: transcript)
        #expect(out == "Hello there.")
    }

    @Test func sanitizedQuoteCollapsesInternalNewlines() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = String(repeating: "x", count: 50)
        let out = service.sanitizedQuoteLine("Line one\nLine two\r\nLine three.", transcript: transcript)
        #expect(out == "Line one Line two Line three.")
    }

    @Test func sanitizedQuoteDropsMidWordTruncation() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        // The model ran out of output tokens mid-word — no terminal punctuation,
        // no recoverable complete sentence. Drop the quote rather than show a partial.
        let transcript = String(repeating: "x", count: 500)
        let out = service.sanitizedQuoteLine(
            "I cannot describe to you my sensations on the near prospect of my undertaking it is impossible to communicate to you a conception of the tre",
            transcript: transcript
        )
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteTrimsToLastCompleteSentenceWhenTailIsPartial() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = String(repeating: "x", count: 500)
        let out = service.sanitizedQuoteLine(
            "She closed the door behind her. He followed without a word, but his hand trem",
            transcript: transcript
        )
        #expect(out == "She closed the door behind her.")
    }

    @Test func sanitizedQuoteDropsOverlongQuoteWithNoTerminator() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        // No terminator in the input — there is no safe sentence to extract, so drop.
        let long = String(repeating: "z", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = service.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteKeepsFirstCompleteSentenceFromOverlongQuote() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let firstSentence = "She walked into the storm without looking back."
        let long = firstSentence + " " + String(repeating: "x", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = service.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out == firstSentence)
    }

    @Test func sanitizedQuoteDropsTranscriptSizedQuoteWithoutCleanSentence() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        // High ratio triggers the overlong branch; "Hi." is too short to be a usable
        // quote (< 20 chars after trim), and the rest has no terminator.
        let transcript = "ab"
        let quote = "Hi." + String(repeating: "x", count: 220)
        let out = service.sanitizedQuoteLine(quote, transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteReturnsEmptyForEmptyInput() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let out = service.sanitizedQuoteLine("", transcript: "anything")
        #expect(out.isEmpty)
    }

    // MARK: - firstSentence

    @Test func firstSentenceExtractsUpToFirstPeriod() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let prefix = String(repeating: "a", count: 25)
        let text = prefix + ". trailing ignored here"
        let out = service.firstSentence(in: text, maxLength: 140)
        #expect(out == prefix + ".")
    }

    @Test func firstSentenceExtractsUpToExclamation() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let prefix = String(repeating: "b", count: 25)
        let text = prefix + "! more text"
        let out = service.firstSentence(in: text, maxLength: 140)
        #expect(out == prefix + "!")
    }

    @Test func firstSentenceTruncatesToMaxLengthWhenNoTerminator() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let text = "abcdefghijklmnopqrstuvwxyz"
        let out = service.firstSentence(in: text, maxLength: 10)
        #expect(out == "abcdefghij")
    }

    // MARK: - trimToCompleteSentences

    @Test func trimNotePassesThroughCompleteNote() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let note = "Victor decides to embark on a perilous voyage. The moment marks a turning point in his life."
        let out = service.trimToCompleteSentences(note)
        #expect(out == note)
    }

    @Test func trimNoteCutsBackToLastFullSentenceWhenTailIsTruncated() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        // Mirrors the truncation seen on-device when the model exhausts its output budget
        // mid-sentence after generating the longer second sentence.
        let note = "Victor decides to embark on a perilous voyage. This moment is pivotal as it marks a significant turning point in his life, highlighting the tension between personal"
        let out = service.trimToCompleteSentences(note)
        #expect(out == "Victor decides to embark on a perilous voyage.")
    }

    @Test func trimNoteAppendsEllipsisWhenNoCompleteSentenceExists() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let note = "Victor decides to embark on a perilous voyage and"
        let out = service.trimToCompleteSentences(note)
        #expect(out.hasSuffix("…"))
        #expect(!out.contains("..."))
    }

    @Test func trimNoteReturnsEmptyForEmptyInput() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        #expect(service.trimToCompleteSentences("").isEmpty)
        #expect(service.trimToCompleteSentences("   \n  ").isEmpty)
    }

    // MARK: - verifiedQuote

    @Test func verifiedQuoteKeepsQuotePresentInTranscript() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
        let out = service.verifiedQuote("The storm broke over the harbor at midnight, and nobody slept.", transcript: transcript)
        #expect(out == "The storm broke over the harbor at midnight, and nobody slept.")
    }

    @Test func verifiedQuoteIsCaseAndPunctuationInsensitive() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
        let out = service.verifiedQuote("the storm broke over the harbor at midnight and nobody slept.", transcript: transcript)
        #expect(!out.isEmpty)
    }

    @Test func verifiedQuoteSnapsParaphraseToTranscriptSentence() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
        // Model dropped words — most of the words still come from one transcript sentence.
        let out = service.verifiedQuote("Storm broke over harbor at midnight, nobody slept!", transcript: transcript)
        #expect(out == "The storm broke over the harbor at midnight, and nobody slept.")
    }

    @Test func verifiedQuoteDropsFabricatedQuote() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
        let out = service.verifiedQuote("To be or not to be, that is the question.", transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func verifiedQuoteDropsVeryShortNonVerbatimQuote() {
        guard #available(iOS 26, *) else { return }
        let service = MomentNamingService()
        let transcript = "The storm broke over the harbor at midnight, and nobody slept."
        let out = service.verifiedQuote("Harbor explosions!", transcript: transcript)
        #expect(out.isEmpty)
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

    @Test func categoryGuideValuesMatchEnum() {
        guard #available(iOS 26, *) else { return }
        #expect(MomentNamingService.categoryGuideValues == MomentCategory.allCases.map(\.rawValue))
    }

    @Test func moodGuideValuesMatchEnum() {
        guard #available(iOS 26, *) else { return }
        #expect(MomentNamingService.moodGuideValues == MomentMood.allCases.map(\.rawValue))
    }
}
