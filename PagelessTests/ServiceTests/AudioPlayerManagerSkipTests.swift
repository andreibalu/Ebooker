//
//  AudioPlayerManagerSkipTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct AudioPlayerManagerSkipTests {

    private func makeTrack(index: Int = 0, duration: Double = 600) -> AudioTrack {
        AudioTrack(
            title: "T\(index)",
            originalFileName: "f\(index).mp3",
            storedFileName: "f\(index).mp3",
            orderIndex: index,
            duration: duration
        )
    }

    private func makeBook(trackCount: Int) -> Audiobook {
        let tracks = (0..<trackCount).map { makeTrack(index: $0) }
        return Audiobook(title: "Test", folderName: "test", totalDuration: 600 * Double(trackCount), tracks: tracks)
    }

    // MARK: - Single-track navigation

    @Test func canGoToNextTrackIsFalseForSingleTrackBook() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 60)

        #expect(player.canGoToNextTrack == false)
    }

    @Test func canGoToPreviousTrackIsFalseForSingleTrackBookEvenAfterFiveSeconds() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        // currentTime > 5 would normally enable "previous" (restart current track),
        // but single-track books should disable the button entirely.
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 60)

        #expect(player.canGoToPreviousTrack == false)
    }

    @Test func canGoToPreviousTrackRespectsTimeForMultiTrackBook() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 3)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 60)

        #expect(player.canGoToPreviousTrack == true)
    }

    @Test func canGoToNextTrackIsTrueForMultiTrackBookNotAtEnd() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 3)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 0)

        #expect(player.canGoToNextTrack == true)
    }

    // MARK: - Preset-interval skip does not arm seek penalty

    @Test func skipBackwardDoesNotArmProgressSeekPenalty() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        player.persistence.seekPenaltyRemaining = 0

        player.skipBackward()

        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    @Test func skipForwardDoesNotArmProgressSeekPenalty() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        player.persistence.seekPenaltyRemaining = 0

        player.skipForward()

        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    @Test func explicitSeekStillArmsProgressSeekPenalty() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        player.persistence.seekPenaltyRemaining = 0

        // Scrubbing via the slider goes through seek(to:) with the default penalty applied.
        player.seek(to: 200)

        #expect(player.persistence.seekPenaltyRemaining == PlaybackPersistence.progressSeekPenalty)
    }
}
