//
//  ComebackVoicePromptTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct ComebackVoicePromptTests {
    @Test func detectsCommonYesPhrases() {
        #expect(ComebackVoicePrompt.answerSaysYes("yes"))
        #expect(ComebackVoicePrompt.answerSaysYes("Yes please"))
        #expect(ComebackVoicePrompt.answerSaysYes("Yeah"))
        #expect(ComebackVoicePrompt.answerSaysYes("yep go ahead"))
        #expect(ComebackVoicePrompt.answerSaysYes("Sure"))
        #expect(ComebackVoicePrompt.answerSaysYes("Okay"))
    }

    @Test func detectsCommonNoPhrases() {
        #expect(!ComebackVoicePrompt.answerSaysYes("no"))
        #expect(!ComebackVoicePrompt.answerSaysYes("Nope"))
        #expect(!ComebackVoicePrompt.answerSaysYes("Skip"))
        #expect(!ComebackVoicePrompt.answerSaysYes("not now"))
        #expect(!ComebackVoicePrompt.answerSaysYes("don't bother"))
    }

    @Test func defaultsToNoOnUnrelatedAnswer() {
        #expect(!ComebackVoicePrompt.answerSaysYes("what was that"))
        #expect(!ComebackVoicePrompt.answerSaysYes(""))
        #expect(!ComebackVoicePrompt.answerSaysYes("hello there"))
    }

    @Test func noBeatsYesWhenBothPresent() {
        // "no, yes" should be safe: an explicit "no" cancels.
        #expect(!ComebackVoicePrompt.answerSaysYes("no, yes"))
    }
}

struct ComebackPromptSheetAnchorTests {
    @Test func includesLocationAndCharactersWhenBothPresent() {
        let recap = ComebackRecapResult(
            location: "the abandoned manor",
            characters: ["Alice"],
            summary: ""
        )
        #expect(ComebackPromptSheet.anchorLine(recap) == "You're in the abandoned manor with Alice.")
    }

    @Test func twoCharactersUsesAnd() {
        let recap = ComebackRecapResult(
            location: "the train",
            characters: ["Alice", "Bob"],
            summary: ""
        )
        #expect(ComebackPromptSheet.anchorLine(recap) == "You're in the train with Alice and Bob.")
    }

    @Test func threePlusCharactersUsesOxfordList() {
        let recap = ComebackRecapResult(
            location: "the tavern",
            characters: ["Alice", "Bob", "Carol"],
            summary: ""
        )
        #expect(ComebackPromptSheet.anchorLine(recap) == "You're in the tavern with Alice, Bob, and Carol.")
    }

    @Test func dropsLocationWhenEmpty() {
        let recap = ComebackRecapResult(location: "", characters: ["Alice"], summary: "")
        #expect(ComebackPromptSheet.anchorLine(recap) == "You're with Alice.")
    }

    @Test func dropsCharactersWhenEmpty() {
        let recap = ComebackRecapResult(location: "the cellar", characters: [], summary: "")
        #expect(ComebackPromptSheet.anchorLine(recap) == "You're in the cellar.")
    }

    @Test func emptyResultProducesEmptyAnchor() {
        let recap = ComebackRecapResult(location: "", characters: [], summary: "")
        #expect(ComebackPromptSheet.anchorLine(recap).isEmpty)
    }
}
