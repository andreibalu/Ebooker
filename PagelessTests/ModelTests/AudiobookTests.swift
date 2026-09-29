//
//  AudiobookTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct AudiobookTests {

    @Test func progressAndRemainingDurationFollowListenedTime() {
        let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
        let book = Audiobook(title: "Test", folderName: "test", totalDuration: 100, currentTime: 50, tracks: [track])
        // listenedDuration = min(0 + 50, 100) = 50
        #expect(book.progress == 0.5)
        #expect(book.remainingDuration == 50)
        #expect(book.progressListenedDuration == 0)

        #expect(Audiobook(title: "Empty", folderName: "empty", totalDuration: 0).progress == 0)
    }

    @Test func displayAuthorFallsBackToUnknown() {
        #expect(Audiobook(title: "Test", author: "", folderName: "test").displayAuthor == "Unknown author")
        #expect(Audiobook(title: "Test", author: "Jane Doe", folderName: "test").displayAuthor == "Jane Doe")
    }

    @Test func isFavoriteCanBeToggled() {
        let book = Audiobook(title: "Test", folderName: "test")
        book.isFavorite = true
        #expect(book.isFavorite == true)
        book.isFavorite = false
        #expect(book.isFavorite == false)
    }

    @Test func currentTrackTitleFallbackWhenNoTracks() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.currentTrackTitle == "Ready to play")
    }

    @Test func castListIsEmptyWithNoMoments() {
        let book = Audiobook(title: "Test", folderName: "test")
        #expect(book.castList.isEmpty)
    }
}
