//
//  RecapServiceLogicTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct RecapServiceLogicTests {

    @Test func sanitizeHeadlineTrimsAndKeepsAtMostFourWords() {
        guard #available(iOS 26, *) else { return }
        #expect(RecapService.sanitizeHeadline("alpha beta gamma delta epsilon zeta") == "alpha beta gamma delta")
        #expect(RecapService.sanitizeHeadline("   left right   ") == "left right")
        #expect(RecapService.sanitizeHeadline("").isEmpty)
    }

}
