//
//  AIResponseTextTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// The model now answers in plain labeled lines (the only output the permissive guardrails
/// cover), so the app parses text instead of decoding a schema. Ways that parsing breaks, one
/// test each: markdown decoration around labels, values that wrap onto the next line, a refusal
/// read as a title, "none" kept as a value, a clipped last sentence shown as-is, and a transcript
/// window that opens mid-sentence.
struct AIResponseTextTests {
    @Test func labeledFieldsTolerateMarkdownCaseAndBullets() {
        let reply = """
        **Title:** The Harbour at Night
        - mood: Tense
        2. CATEGORIES: action, plot twist
        """
        let fields = AIResponseText.labeledFields(in: reply, labels: ["Title", "Mood", "Categories"])
        #expect(fields["title"] == "The Harbour at Night")
        #expect(fields["mood"] == "Tense")
        #expect(fields["categories"] == "action, plot twist")
    }

    @Test func labeledFieldsJoinContinuationLinesAndIgnoreUnknownLabels() {
        let reply = """
        Title: Arrival
        Note: Ariadne reaches the harbour.
        She finds the lantern still lit.
        Rating: 5
        """
        let fields = AIResponseText.labeledFields(in: reply, labels: ["Title", "Note"])
        #expect(fields["note"] == "Ariadne reaches the harbour. She finds the lantern still lit.")
        #expect(fields["rating"] == nil)
    }

    @Test func unlabeledProseGoesToTheOverflowField() {
        // Seen on device: the model writes the note without its label, right after the quote.
        let reply = """
        Quote: "The storm broke over the harbor."
        The town stays awake. Ariadne lights the lantern.
        """
        let fields = AIResponseText.labeledFields(in: reply, labels: ["Quote", "Note"], overflowLabel: "Note")
        #expect(fields["quote"] == "\"The storm broke over the harbor.\"")
        #expect(fields["note"] == "The town stays awake. Ariadne lights the lantern.")

        // A clock time is not a label: "At 10:30" once read as the label "At" and the line was lost.
        let timed = AIResponseText.labeledFields(
            in: "Title: Night\nAt 10:30 the clock struck. Everyone slept.",
            labels: ["Title", "Note"],
            overflowLabel: "Note"
        )
        #expect(timed["note"] == "At 10:30 the clock struck. Everyone slept.")
    }

    /// Seen as a failure mode: a preamble overflowed into the recap ("Here's a recap:…") and
    /// the unlabeled prose then joined the headline.
    @Test func preambleLinesAreNotValues() {
        let reply = "Here's a recap:\nHeadline: At the river\nJane waits by the water. Bingley arrives late."
        let fields = AIResponseText.labeledFields(in: reply, labels: ["Headline", "Recap"], overflowLabel: "Recap")
        #expect(fields["headline"] == "At the river")
        #expect(fields["recap"] == "Jane waits by the water. Bingley arrives late.")
    }

    @Test func refusalsAreRecognized() {
        #expect(AIResponseText.isRefusal("I'm sorry, but I can't help with that request."))
        #expect(AIResponseText.isRefusal("I apologize, but I cannot assist with this."))
        #expect(AIResponseText.isRefusal("As an AI language model, I can't describe this content."))
        // Missed openers made a refusal `.failed`, which skips the retry on the passage tail.
        #expect(AIResponseText.isRefusal("Unfortunately, I can't help with this passage."))
        #expect(AIResponseText.isRefusal("I’m afraid I can’t describe this."))
        #expect(AIResponseText.isRefusal("Unfortunately, I'm unable to summarize this."))
        #expect(AIResponseText.isRefusal("Sorry, I can't describe this passage."))
        #expect(AIResponseText.isRefusal("I'm afraid I can't help with that."))
        #expect(!AIResponseText.isRefusal("Title: Sorry Is the Hardest Word\nMood: sad"))
    }

    /// An opener must end at a word boundary: "Unfortunately, it rains" and "I'm afraid it is too
    /// late" are recap and note prose, and "unfortunately, i" also prefixes "unfortunately, isabel".
    @Test func proseThatOnlyStartsLikeARefusalIsKept() {
        #expect(!AIResponseText.isRefusal("Unfortunately, it rains on the day of the ball."))
        #expect(!AIResponseText.isRefusal("Unfortunately, Isabel arrives too late to stop the wedding."))
        #expect(!AIResponseText.isRefusal("Sorry, it was never his to give."))
        #expect(!AIResponseText.isRefusal("I'm afraid it is too late."))
    }

    @Test func listsDropPlaceholdersAndDuplicates() {
        #expect(AIResponseText.list("none").isEmpty)
        #expect(AIResponseText.list("N/A").isEmpty)
        #expect(AIResponseText.list("Elizabeth, Mr. Darcy and Jane, elizabeth") == ["Elizabeth", "Mr. Darcy", "Jane"])
    }

    @Test func titlesLoseQuotesTrailingPeriodAndExcessWords() {
        #expect(AIResponseText.cleanTitle("\"The Harbour at Night.\"") == "The Harbour at Night")
        #expect(AIResponseText.cleanTitle("A Very Long Title That Keeps Going On and On Forever") == "A Very Long Title That Keeps Going")
        #expect(AIResponseText.cleanTitle("none") == "")
        // Seen on device: a 4-word cut of a longer headline ended on a joiner.
        #expect(AIResponseText.cleanTitle("Catherine and Heathcliff at the door", maxWords: 4) == "Catherine and Heathcliff")
        // Seen on the real model: a plain cut stopped mid-phrase on a possessive or a preposition.
        #expect(AIResponseText.cleanTitle("Bingley's arrival and Jane's reaction", maxWords: 4) == "Bingley's arrival")
        #expect(AIResponseText.cleanTitle("Jane and Elizabeth near the window", maxWords: 4) == "Jane and Elizabeth")
        #expect(AIResponseText.cleanTitle("dinner in the living room", maxWords: 4) == "dinner")
        // A title within the limit stays whole.
        #expect(AIResponseText.cleanTitle("Mina's vow to Van", maxWords: 4) == "Mina's vow to Van")
    }

    @Test func clippedProseTrimsBackToLastSentence() {
        let note = "Victor decides to embark on a perilous voyage. This moment is pivotal as it marks a significant turning point in his life, highlighting the tension between personal"
        #expect(AIResponseText.trimToCompleteSentences(note) == "Victor decides to embark on a perilous voyage.")
    }

    @Test func transcriptLosesLeadingFragmentAndExtraWhitespace() {
        let raw = "of the night.   The storm broke over the harbor at midnight, and nobody slept.\n Morning came slowly"
        #expect(AIResponseText.cleanTranscript(raw) == "The storm broke over the harbor at midnight, and nobody slept. Morning came slowly")
        // A window that starts on a sentence keeps it.
        #expect(AIResponseText.cleanTranscript("It was late. She waited.") == "It was late. She waited.")
        // A decimal point or an honorific is not a sentence end: cutting there garbled the passage.
        let decimal = "about 3.5 miles away it stood. The house was dark and silent and Elizabeth stood outside alone."
        #expect(AIResponseText.cleanTranscript(decimal) == "The house was dark and silent and Elizabeth stood outside alone.")
        let honorific = "and then Mr. Darcy entered the room. Elizabeth looked up from the letter at him. She said nothing for a long while."
        #expect(AIResponseText.cleanTranscript(honorific) == "Elizabeth looked up from the letter at him. She said nothing for a long while.")
    }
}
