//
//  RecapServiceComebackTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct RecapServiceComebackTests {
    @Test func sanitizeMapsUnknownLocationToEmpty() {
        let out = RecapService.sanitizeComeback(
            rawLocation: "unknown",
            rawCharacters: ["Alice"],
            rawSummary: "Alice opened the door."
        )
        #expect(out.location.isEmpty)
        #expect(out.characters == ["Alice"])
        #expect(out.summary == "Alice opened the door.")
    }

    @Test func sanitizeMapsCaseInsensitiveUnknownToEmpty() {
        let out = RecapService.sanitizeComeback(
            rawLocation: "Unknown",
            rawCharacters: [],
            rawSummary: "Test."
        )
        #expect(out.location.isEmpty)
    }

    @Test func sanitizeTrimsLocationWhitespace() {
        let out = RecapService.sanitizeComeback(
            rawLocation: "  the cellar  ",
            rawCharacters: [],
            rawSummary: "ok"
        )
        #expect(out.location == "the cellar")
    }

    @Test func sanitizeClampsCharactersToFour() {
        let out = RecapService.sanitizeComeback(
            rawLocation: "ship",
            rawCharacters: ["A", "B", "C", "D", "E", "F"],
            rawSummary: "."
        )
        #expect(out.characters.count == 4)
        #expect(out.characters == ["A", "B", "C", "D"])
    }

    @Test func sanitizeDropsEmptyCharacterNames() {
        let out = RecapService.sanitizeComeback(
            rawLocation: "ship",
            rawCharacters: ["Alice", "  ", "", "Bob"],
            rawSummary: "."
        )
        #expect(out.characters == ["Alice", "Bob"])
    }

    @Test func sanitizeTruncatesOversizedSummary() {
        let big = String(repeating: "x", count: 500)
        let out = RecapService.sanitizeComeback(
            rawLocation: "ship",
            rawCharacters: [],
            rawSummary: big
        )
        #expect(out.summary.count <= 350)
    }
}
