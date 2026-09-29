//
//  SamplePlayerTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

@MainActor
struct SamplePlayerTests {
    @Test func beginLoadingShowsImmediateLoadingStateUntilStopped() {
        let player = SamplePlayer.shared
        player.stop()

        player.beginLoading(bookId: "sample-book")
        #expect(player.state == .loading(bookId: "sample-book"))

        player.stop()
        #expect(player.state == .idle)
    }
}
