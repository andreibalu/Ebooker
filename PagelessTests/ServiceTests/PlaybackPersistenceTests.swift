//
//  PlaybackPersistenceTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

@MainActor
struct PlaybackPersistenceTests {
    private func makeAudiobook(tracks: [AudioTrack] = []) -> Audiobook {
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 600, tracks: tracks)
        return book
    }

    @Test func updateProgressBlockedBySeekPenalty() {
        let persistence = PlaybackPersistence()
        let book = makeAudiobook()
        persistence.seekPenaltyRemaining = 180

        persistence.updateProgressIfNeeded(
            audiobook: book,
            currentTrackIndex: 0,
            currentTime: 100,
            duration: 300
        )

        #expect(book.progressTrackIndex == nil)
        #expect(book.progressTime == nil)
    }

}
