//
//  SamplePlayerTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

@MainActor
struct SamplePlayerTests {
    @Test func samplesStartAfterIntroAndKeepTwentySecondDuration() {
        #expect(SamplePlayer.sampleStartOffsetSeconds == 30)
        #expect(SamplePlayer.sampleDurationSeconds == 20)
    }
}
