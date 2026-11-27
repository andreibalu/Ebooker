//
//  RewindPositionTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// Isolated because the multi-track walk (several short tracks, unknown durations, the clamp at
/// the start) needs book shapes the E2E fixtures don't ship.
struct RewindPositionTests {

    private func target(_ track: Int, _ time: Double, _ seconds: Double, _ durations: [Double])
        -> (trackIndex: Int, time: Double) {
        RewindPosition.target(trackIndex: track, time: time, seconds: seconds, trackDurations: durations)
    }

    // Catches: a single-file book (M4B) losing the plain in-track rewind.
    @Test func staysInTheTrackWhenThereIsRoom() {
        let result = target(0, 100, 30, [600])
        #expect(result.trackIndex == 0)
        #expect(result.time == 70)
    }

    // Catches: the old clamp at 0:00 of the current track instead of crossing back.
    @Test func crossesIntoTheEndOfThePreviousTrack() {
        let result = target(1, 10, 30, [600, 600])
        #expect(result.trackIndex == 0)
        #expect(result.time == 580)
    }

    // Catches: stopping after one track when the step is longer than a short earlier track.
    @Test func crossesSeveralShortTracks() {
        let result = target(3, 5, 100, [600, 40, 30, 600])
        // 5 s into track 3, then 30 s (track 2), then 40 s (track 1) leaves 25 s for track 0.
        #expect(result.trackIndex == 0)
        #expect(result.time == 575)
    }

    // Catches: an off-by-one when the step lands exactly on a track start.
    @Test func landingExactlyOnATrackStartStaysOnThatTrack() {
        let result = target(1, 10, 10, [600, 600])
        #expect(result.trackIndex == 1)
        #expect(result.time == 0)
    }

    // Catches: a negative time or a negative track index at the start of the book.
    @Test func clampsAtTheStartOfTheBook() {
        let single = target(0, 5, 30, [600])
        #expect(single.trackIndex == 0)
        #expect(single.time == 0)
        let multi = target(2, 5, 10_000, [50, 50, 50])
        #expect(multi.trackIndex == 0)
        #expect(multi.time == 0)
    }

    // Catches: entering a track whose duration is unknown (0) and landing at a bogus time.
    @Test func neverEntersAnEarlierTrackOfUnknownDuration() {
        let result = target(2, 5, 60, [600, 0, 600])
        #expect(result.trackIndex == 2)
        #expect(result.time == 0)
        let deeper = target(2, 5, 60, [0, 20, 600])
        // Walks into track 1 (20 s), then stops at its start rather than entering track 0.
        #expect(deeper.trackIndex == 1)
        #expect(deeper.time == 0)
    }

    // Catches: a rewind of zero or a bad value moving the playhead.
    @Test func aStepOfZeroOrLessLeavesThePositionAlone() {
        for seconds in [0, -10, Double.nan] as [Double] {
            let result = target(1, 42, seconds, [600, 600])
            #expect(result.trackIndex == 1)
            #expect(result.time == 42)
        }
    }

    // Catches: a crash or a wrong jump when the index points past the stored durations.
    @Test func anIndexOutsideTheDurationsDoesNotCrossBack() {
        let result = target(5, 10, 30, [600, 600])
        #expect(result.trackIndex == 5)
        #expect(result.time == 0)
    }
}
