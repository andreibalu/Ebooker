//
//  PlaybackPersistenceRecapTests.swift
//  EbookerTests
//

import Testing
@testable import Ebooker

@MainActor
struct PlaybackPersistenceRecapTests {
    @Test func advancingProgressMarkerClearsStoredRecap() {
        let book = Audiobook(title: "T", author: "", folderName: "folder", totalDuration: 600)
        let track = AudioTrack(
            title: "1",
            originalFileName: "a.m4a",
            storedFileName: "a.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks = [track]
        book.currentTrackIndex = 0
        book.currentTime = 400
        book.progressTrackIndex = 0
        book.progressTime = 100
        book.storeProgressRecap(text: "Saved summary", headline: "Short name", anchorTrackIndex: 0, anchorTime: 100)

        let persistence = PlaybackPersistence()
        persistence.seekPenaltyRemaining = 0
        persistence.updateProgressIfNeeded(
            audiobook: book,
            currentTrackIndex: 0,
            currentTime: 400,
            duration: 600
        )

        #expect(book.progressRecapText == nil)
        #expect(book.progressRecapHeadline == nil)
        #expect(book.progressTime == 400)
    }

    @Test func markFinishedClearsStoredRecap() {
        let book = Audiobook(title: "T", author: "", folderName: "folder2", totalDuration: 600)
        let track = AudioTrack(
            title: "1",
            originalFileName: "a.m4a",
            storedFileName: "a.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks = [track]
        book.storeProgressRecap(text: "Recap", headline: "Head", anchorTrackIndex: 0, anchorTime: 200)

        let persistence = PlaybackPersistence()
        persistence.markFinished(
            audiobook: book,
            trackIndex: 0,
            duration: 600,
            context: nil
        )

        #expect(book.progressRecapText == nil)
        #expect(book.isFinished == true)
    }
}
