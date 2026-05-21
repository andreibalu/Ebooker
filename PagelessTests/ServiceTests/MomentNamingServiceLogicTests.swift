//
//  MomentNamingServiceLogicTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@available(iOS 26, *)
struct MomentNamingServiceLogicTests {
    private let service = MomentNamingService()

    // MARK: - sanitizedQuoteLine

    @Test func sanitizedQuotePassesThroughNormalQuote() {
        let transcript = String(repeating: "word ", count: 30)
        let out = service.sanitizedQuoteLine("A memorable line from the story.", transcript: transcript)
        #expect(out == "A memorable line from the story.")
    }

    @Test func sanitizedQuoteStripsLeadingTrailingQuoteChars() {
        let transcript = String(repeating: "x", count: 50)
        let out = service.sanitizedQuoteLine("\"“”'Hello there.'”\"", transcript: transcript)
        #expect(out == "Hello there.")
    }

    @Test func sanitizedQuoteCollapsesInternalNewlines() {
        let transcript = String(repeating: "x", count: 50)
        let out = service.sanitizedQuoteLine("Line one\nLine two\r\nLine three.", transcript: transcript)
        #expect(out == "Line one Line two Line three.")
    }

    @Test func sanitizedQuoteDropsMidWordTruncation() {
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
        let transcript = String(repeating: "x", count: 500)
        let out = service.sanitizedQuoteLine(
            "She closed the door behind her. He followed without a word, but his hand trem",
            transcript: transcript
        )
        #expect(out == "She closed the door behind her.")
    }

    @Test func sanitizedQuoteDropsOverlongQuoteWithNoTerminator() {
        // No terminator in the input — there is no safe sentence to extract, so drop.
        let long = String(repeating: "z", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = service.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteKeepsFirstCompleteSentenceFromOverlongQuote() {
        let firstSentence = "She walked into the storm without looking back."
        let long = firstSentence + " " + String(repeating: "x", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = service.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out == firstSentence)
    }

    @Test func sanitizedQuoteDropsTranscriptSizedQuoteWithoutCleanSentence() {
        // High ratio triggers the overlong branch; "Hi." is too short to be a usable
        // quote (< 20 chars after trim), and the rest has no terminator.
        let transcript = "ab"
        let quote = "Hi." + String(repeating: "x", count: 220)
        let out = service.sanitizedQuoteLine(quote, transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteReturnsEmptyForEmptyInput() {
        let out = service.sanitizedQuoteLine("", transcript: "anything")
        #expect(out.isEmpty)
    }

    // MARK: - firstSentence

    @Test func firstSentenceExtractsUpToFirstPeriod() {
        let prefix = String(repeating: "a", count: 25)
        let text = prefix + ". trailing ignored here"
        let out = service.firstSentence(in: text, maxLength: 140)
        #expect(out == prefix + ".")
    }

    @Test func firstSentenceExtractsUpToExclamation() {
        let prefix = String(repeating: "b", count: 25)
        let text = prefix + "! more text"
        let out = service.firstSentence(in: text, maxLength: 140)
        #expect(out == prefix + "!")
    }

    @Test func firstSentenceTruncatesToMaxLengthWhenNoTerminator() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let out = service.firstSentence(in: text, maxLength: 10)
        #expect(out == "abcdefghij")
    }

    // MARK: - trimToCompleteSentences

    @Test func trimNotePassesThroughCompleteNote() {
        let note = "Victor decides to embark on a perilous voyage. The moment marks a turning point in his life."
        let out = service.trimToCompleteSentences(note)
        #expect(out == note)
    }

    @Test func trimNoteCutsBackToLastFullSentenceWhenTailIsTruncated() {
        // Mirrors the truncation seen on-device when the model exhausts its output budget
        // mid-sentence after generating the longer second sentence.
        let note = "Victor decides to embark on a perilous voyage. This moment is pivotal as it marks a significant turning point in his life, highlighting the tension between personal"
        let out = service.trimToCompleteSentences(note)
        #expect(out == "Victor decides to embark on a perilous voyage.")
    }

    @Test func trimNoteAppendsEllipsisWhenNoCompleteSentenceExists() {
        let note = "Victor decides to embark on a perilous voyage and"
        let out = service.trimToCompleteSentences(note)
        #expect(out.hasSuffix("…"))
        #expect(!out.contains("..."))
    }

    @Test func trimNoteReturnsEmptyForEmptyInput() {
        #expect(service.trimToCompleteSentences("").isEmpty)
        #expect(service.trimToCompleteSentences("   \n  ").isEmpty)
    }
}
