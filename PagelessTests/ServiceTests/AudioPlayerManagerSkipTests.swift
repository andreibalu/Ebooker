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

    // MARK: - Unloading a deleted book

    @Test func unloadIfCurrentCancelsADownloadedBookStillPreparing() {
        let player = AudioPlayerManager()
        let playing = makeBook(trackCount: 1)
        let preparing = makeBook(trackCount: 1)
        // A downloaded book that is still preparing has a pending target but no loading ID,
        // and the player still shows the previous book.
        player.seedUnitTestPlaybackState(audiobook: playing, track: playing.sortedTracks[0], trackIndex: 0, currentTime: 10)
        player.seedUnitTestPendingPlaybackTarget(PendingPlaybackTarget(bookID: preparing.id, trackIndex: 0, time: 0))

        player.unloadIfCurrent(preparing)

        #expect(player.pendingPlaybackTarget == nil)
        #expect(player.currentAudiobook == nil)
    }

    // MARK: - Preset-interval skip and the progress-save penalty

    @Test func skipBackwardKeepsPenaltyZeroWhenProgressIsSaving() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        player.persistence.seekPenaltyRemaining = 0

        player.skipBackward()

        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    @Test func skipForwardKeepsPenaltyZeroWhenProgressIsSaving() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        player.persistence.seekPenaltyRemaining = 0

        player.skipForward()

        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    @Test func skipBackwardResetsPenaltyWhenAlreadyPenalized() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        // Simulate a recent scrub that paused progress saving with some time left.
        player.persistence.seekPenaltyRemaining = 30

        player.skipBackward()

        #expect(player.persistence.seekPenaltyRemaining == PlaybackPersistence.progressSeekPenalty)
    }

    @Test func skipForwardResetsPenaltyWhenAlreadyPenalized() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 120)
        player.persistence.seekPenaltyRemaining = 30

        player.skipForward()

        #expect(player.persistence.seekPenaltyRemaining == PlaybackPersistence.progressSeekPenalty)
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
