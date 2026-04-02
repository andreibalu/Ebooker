//
//  AudiobookTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct AudiobookTests {
    @Test func progressIsZeroForNewAudiobook() {
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 100)
        #expect(book.progress == 0)
    }

    @Test func progressComputesCorrectly() {
        let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 100, currentTime: 50, tracks: [track])
        // listenedDuration = min(0 + 50, 100) = 50
        #expect(book.progress == 0.5)
    }

    @Test func progressIsZeroWhenTotalDurationIsZero() {
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 0)
        #expect(book.progress == 0)
    }

    @Test func remainingDurationComputesCorrectly() {
        let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 100, currentTime: 30, tracks: [track])
        #expect(book.remainingDuration == 70)
    }

    @Test func displayAuthorFallsBackToUnknown() {
        let book = Audiobook(title: "Test", author: "", folderName: "test")
        #expect(book.displayAuthor == "Unknown author")
    }

    @Test func displayAuthorUsesActualAuthor() {
        let book = Audiobook(title: "Test", author: "Jane Doe", folderName: "test")
        #expect(book.displayAuthor == "Jane Doe")
    }

    @Test func isFavoriteDefaultsToFalse() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.isFavorite == false)
    }

    @Test func isFavoriteCanBeToggled() {
        let book = Audiobook(title: "Test", folderName: "test")
        book.isFavorite = true
        #expect(book.isFavorite == true)
        book.isFavorite = false
        #expect(book.isFavorite == false)
    }

    @Test func isFinishedDefaultsToFalse() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.isFinished == false)
    }

    @Test func currentTrackTitleFallbackWhenNoTracks() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.currentTrackTitle == "Ready to play")
    }

    @Test func castListIsEmptyWithNoMoments() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.castList.isEmpty)
    }

    @Test func progressListenedDurationIsZeroWithNoProgress() {
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 100)
        #expect(book.progressListenedDuration == 0)
    }
}
