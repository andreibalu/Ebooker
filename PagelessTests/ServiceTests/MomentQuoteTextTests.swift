//
//  MomentQuoteTextTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// Isolated on purpose: the card pixels aren't readable from E2E, and the doubled-quote bug
/// only shows with stored quotes that already carry quote marks.
struct MomentQuoteTextTests {
    @Test func stripsStraightAndCurlyMarksOnBothEnds() {
        #expect(MomentQuoteText.stripped("\"Call me Ishmael.\"") == "Call me Ishmael.")
        #expect(MomentQuoteText.stripped("\u{201C}Call me Ishmael.\u{201D}") == "Call me Ishmael.")
        #expect(MomentQuoteText.stripped("  \u{201C}\u{201C}Call me\u{201D}\u{201D}  \n") == "Call me")
        #expect(MomentQuoteText.stripped("\u{201C}Only opening mark") == "Only opening mark")
    }

    @Test func keepsInnerMarksAndApostrophes() {
        #expect(MomentQuoteText.stripped("He said \"go\" and left.") == "He said \"go\" and left.")
        #expect(MomentQuoteText.stripped("the dogs\u{2019} bark") == "the dogs\u{2019} bark")
        #expect(MomentQuoteText.stripped("\"Rock 'n' roll\"") == "Rock 'n' roll")
    }

    @Test func emptyOrMarksOnlyIsNil() {
        #expect(MomentQuoteText.stripped(nil) == nil)
        #expect(MomentQuoteText.stripped("   ") == nil)
        #expect(MomentQuoteText.stripped("\"\" \u{201C}\u{201D}") == nil)
        #expect(MomentQuoteText.decorated("\"\"") == nil)
    }

    @Test func decoratedWrapsExactlyOnePair() {
        #expect(MomentQuoteText.decorated("Call me Ishmael.") == "\u{201C}Call me Ishmael.\u{201D}")
        #expect(MomentQuoteText.decorated("\"Call me Ishmael.\"") == "\u{201C}Call me Ishmael.\u{201D}")
    }

    @Test func cardPayloadDropsStoredQuoteMarks() {
        let payload = MomentQuoteCardPayload(
            bookTitle: "Moby-Dick", author: "Melville", coverArtData: nil,
            quoteLine: "\u{201C}Call me Ishmael.\u{201D}", label: "Opening", note: nil,
            chapterTitle: nil, timestamp: "00:05"
        )
        #expect(payload.quoteLine == "Call me Ishmael.")
        let onlyMarks = MomentQuoteCardPayload(
            bookTitle: "B", author: "", coverArtData: nil, quoteLine: "\"\"", label: "L", note: nil,
            chapterTitle: nil, timestamp: "00:05"
        )
        #expect(onlyMarks.quoteLine == nil)
    }
}
