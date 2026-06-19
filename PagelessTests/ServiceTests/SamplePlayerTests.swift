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

    @Test func beginLoadingShowsImmediateLoadingState() {
        let player = SamplePlayer.shared
        player.stop()

        player.beginLoading(bookId: "sample-book")

        #expect(player.state == .loading(bookId: "sample-book"))
        player.stop()
    }

    @Test func stopClearsImmediateLoadingState() {
        let player = SamplePlayer.shared
        player.stop()
        player.beginLoading(bookId: "sample-book")

        player.stop()

        #expect(player.state == .idle)
    }
}
