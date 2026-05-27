//
//  RecapServiceLogicTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct RecapServiceLogicTests {
    @Test func sanitizeHeadlineKeepsFourWords() {
        guard #available(iOS 26, *) else { return }
        let out = RecapService.sanitizeHeadline("one two three four")
        #expect(out == "one two three four")
    }

    @Test func sanitizeHeadlineTruncatesToFourWords() {
        guard #available(iOS 26, *) else { return }
        let out = RecapService.sanitizeHeadline("alpha beta gamma delta epsilon zeta")
        #expect(out == "alpha beta gamma delta")
    }

    @Test func sanitizeHeadlineTrimsWhitespace() {
        guard #available(iOS 26, *) else { return }
        let out = RecapService.sanitizeHeadline("   left right   ")
        #expect(out == "left right")
    }

    @Test func sanitizeHeadlineHandlesEmptyString() {
        guard #available(iOS 26, *) else { return }
        let out = RecapService.sanitizeHeadline("")
        #expect(out.isEmpty)
    }

    @Test func sanitizeHeadlineHandlesSingleWord() {
        guard #available(iOS 26, *) else { return }
        let out = RecapService.sanitizeHeadline("Hello")
        #expect(out == "Hello")
    }
}
