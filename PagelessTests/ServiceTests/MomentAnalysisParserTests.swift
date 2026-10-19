//
//  MomentAnalysisParserTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct MomentAnalysisParserTests {

    // MARK: - sanitizedQuoteLine

    @Test func sanitizedQuoteDropsMidWordTruncation() {
        // The model ran out of output tokens mid-word — no terminal punctuation,
        // no recoverable complete sentence. Drop the quote rather than show a partial.
        let transcript = String(repeating: "x", count: 500)
        let out = MomentAnalysisParser.sanitizedQuoteLine(
            "I cannot describe to you my sensations on the near prospect of my undertaking it is impossible to communicate to you a conception of the tre",
            transcript: transcript
        )
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteTrimsToLastCompleteSentenceWhenTailIsPartial() {
        let transcript = String(repeating: "x", count: 500)
        let out = MomentAnalysisParser.sanitizedQuoteLine(
            "She closed the door behind her. He followed without a word, but his hand trem",
            transcript: transcript
        )
        #expect(out == "She closed the door behind her.")
    }

    @Test func sanitizedQuoteDropsOverlongQuoteWithNoTerminator() {
        // No terminator in the input — there is no safe sentence to extract, so drop.
        let long = String(repeating: "z", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = MomentAnalysisParser.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func sanitizedQuoteKeepsFirstCompleteSentenceFromOverlongQuote() {
        let firstSentence = "She walked into the storm without looking back."
        let long = firstSentence + " " + String(repeating: "x", count: 230)
        let transcript = String(repeating: "a", count: 1_000)
        let out = MomentAnalysisParser.sanitizedQuoteLine(long, transcript: transcript)
        #expect(out == firstSentence)
    }

    @Test func sanitizedQuoteDropsTranscriptSizedQuoteWithoutCleanSentence() {
        // High ratio triggers the overlong branch; "Hi." is too short to be a usable
        // quote (< 20 chars after trim), and the rest has no terminator.
        let transcript = "ab"
        let quote = "Hi." + String(repeating: "x", count: 220)
        let out = MomentAnalysisParser.sanitizedQuoteLine(quote, transcript: transcript)
        #expect(out.isEmpty)
    }

    // MARK: - verifiedQuote

    @Test func verifiedQuoteKeepsQuotePresentInTranscript() {
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
        let out = MomentAnalysisParser.verifiedQuote("The storm broke over the harbor at midnight, and nobody slept.", transcript: transcript)
        #expect(out == "The storm broke over the harbor at midnight, and nobody slept.")
    }

    @Test func verifiedQuoteIsCaseAndPunctuationInsensitive() {
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
        let out = MomentAnalysisParser.verifiedQuote("the storm broke over the harbor at midnight and nobody slept.", transcript: transcript)
        #expect(!out.isEmpty)
    }

    @Test func verifiedQuoteSnapsParaphraseToTranscriptSentence() {
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
        // Model dropped words — most of the words still come from one transcript sentence.
        let out = MomentAnalysisParser.verifiedQuote("Storm broke over harbor at midnight, nobody slept!", transcript: transcript)
        #expect(out == "The storm broke over the harbor at midnight, and nobody slept.")
    }

    @Test func verifiedQuoteDropsFabricatedQuote() {
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
        let out = MomentAnalysisParser.verifiedQuote("To be or not to be, that is the question.", transcript: transcript)
        #expect(out.isEmpty)
    }

    @Test func verifiedQuoteDropsVeryShortNonVerbatimQuote() {
        let transcript = "The storm broke over the harbor at midnight, and nobody slept."
        let out = MomentAnalysisParser.verifiedQuote("Harbor explosions!", transcript: transcript)
        #expect(out.isEmpty)
    }

    // MARK: - parse

    @Test func parseMapsLabeledReplyOntoAnalysis() {
        let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Ariadne lit the lantern."
        let reply = """
        Title: Storm Over the Harbor
        Mood: Mysterious
        Categories: world building, Plot Twist, gossip
        Characters: Ariadne, the harbourmaster, sailors,
        Quote: The storm broke over the harbor at midnight, and nobody slept.
        A storm keeps the town awake. Ariadne lights the lantern for the ships.
        """
        let analysis = MomentAnalysisParser.parse(reply, transcript: transcript)
        #expect(analysis?.name == "Storm Over the Harbor")
        #expect(analysis?.mood == .mysterious)
        // Spelled-out category names map onto the enum; unknown ones are dropped.
        #expect(analysis?.categories == [.worldBuilding, .plotTwist])
        // Roles are not names; a trailing comma adds nothing.
        #expect(analysis?.characters == ["Ariadne"])
        #expect(analysis?.quoteLine == "The storm broke over the harbor at midnight, and nobody slept.")
        // The note arrived without its label.
        #expect(analysis?.note == "A storm keeps the town awake. Ariadne lights the lantern for the ships.")
    }

    @Test func parseRejectsRefusalsAndRepliesWithoutTitle() {
        #expect(MomentAnalysisParser.parse("I'm sorry, but I can't help with that.", transcript: "t") == nil)
        #expect(MomentAnalysisParser.parse("Mood: tense\nNote: Something happens.", transcript: "t") == nil)
        #expect(MomentAnalysisParser.parse("Title: I'm sorry, but I can't help with that.", transcript: "t") == nil)
        // Fiction titles open like refusals; they are still names.
        #expect(MomentAnalysisParser.parse("Title: I Won't Go Back\nMood: tense", transcript: "t")?.name == "I Won't Go Back")
    }

    /// A preamble must not claim the note, or the unlabeled note joins the title.
    @Test func preambleLineDoesNotPushTheNoteIntoTheTitle() {
        let reply = "Here is the analysis:\nTitle: The Proposal\nDarcy proposes and Elizabeth refuses.\nMood: tense"
        let analysis = MomentAnalysisParser.parse(reply, transcript: "t")
        #expect(analysis?.name == "The Proposal")
        #expect(analysis?.note == "Darcy proposes and Elizabeth refuses.")
    }
}
