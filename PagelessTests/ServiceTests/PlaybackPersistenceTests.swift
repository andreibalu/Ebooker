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

    @Test func updateProgressAdvancesWhenPenaltyIsZero() {
        let persistence = PlaybackPersistence()
        let book = makeAudiobook()
        persistence.seekPenaltyRemaining = 0

        persistence.updateProgressIfNeeded(
            audiobook: book,
            currentTrackIndex: 0,
            currentTime: 100,
            duration: 300
        )

        #expect(book.progressTrackIndex == 0)
        #expect(book.progressTime == 100)
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

    @Test func persistSkipsWhenDeltaIsSmall() {
        let persistence = PlaybackPersistence()
        let book = makeAudiobook()
        persistence.lastPersistedTime = 100

        persistence.persist(
            audiobook: book,
            trackIndex: 0,
            time: 103,
            duration: 600,
            rate: 1.0,
            force: false,
            context: nil
        )

        // lastPersistedTime should NOT change since delta < 5
        #expect(persistence.lastPersistedTime == 100)
    }

    @Test func persistSavesWhenForced() {
        let persistence = PlaybackPersistence()
        let book = makeAudiobook()
        persistence.lastPersistedTime = 100

        persistence.persist(
            audiobook: book,
            trackIndex: 0,
            time: 101,
            duration: 600,
            rate: 1.0,
            force: true,
            context: nil
        )

        // With no context, save() is a no-op but the model fields should be set
        #expect(book.currentTrackIndex == 0)
        #expect(book.currentTime == 101)
        #expect(book.isFinished == false)
    }

    @Test func markFinishedSetsCorrectState() {
        let persistence = PlaybackPersistence()
        let book = makeAudiobook()

        persistence.markFinished(
            audiobook: book,
            trackIndex: 2,
            duration: 600,
            context: nil
        )

        #expect(book.isFinished == true)
        #expect(book.currentTrackIndex == 2)
        #expect(book.currentTime == 600)
        #expect(book.progressTrackIndex == 2)
        #expect(book.progressTime == 600)
        #expect(book.progressUpdatedAt != nil)
    }

    @Test func seekPenaltyConstant() {
        #expect(PlaybackPersistence.progressSeekPenalty == 180)
    }
}
