//
//  AudiobookAdditionalTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct AudiobookAdditionalTests {
    @Test func sortedTracksOrdersByOrderIndex() {
        let t2 = AudioTrack(title: "B", originalFileName: "b", storedFileName: "b", orderIndex: 2, duration: 10)
        let t0 = AudioTrack(title: "A", originalFileName: "a", storedFileName: "a", orderIndex: 0, duration: 10)
        let t1 = AudioTrack(title: "C", originalFileName: "c", storedFileName: "c", orderIndex: 1, duration: 10)
        let book = Audiobook(title: "Sort", folderName: "s", totalDuration: 100, tracks: [t2, t0, t1])
        let titles = book.sortedTracks.map(\.title)
        #expect(titles == ["A", "C", "B"])
    }

    @Test func listenedDurationSumsCompletedTracks() {
        let t0 = AudioTrack(title: "T0", originalFileName: "a", storedFileName: "a", orderIndex: 0, duration: 100)
        let t1 = AudioTrack(title: "T1", originalFileName: "b", storedFileName: "b", orderIndex: 1, duration: 200)
        let book = Audiobook(
            title: "Listen",
            folderName: "l",
            totalDuration: 500,
            currentTrackIndex: 1,
            currentTime: 50,
            tracks: [t0, t1]
        )
        // Completed: orderIndex < 1 → 100s; plus 50s on current track
        #expect(book.listenedDuration == 150)
    }

    @Test func progressListenedDurationWithTracks() {
        let t0 = AudioTrack(title: "T0", originalFileName: "a", storedFileName: "a", orderIndex: 0, duration: 80)
        let t1 = AudioTrack(title: "T1", originalFileName: "b", storedFileName: "b", orderIndex: 1, duration: 120)
        let book = Audiobook(title: "Prog", folderName: "p", totalDuration: 400, tracks: [t0, t1])
        book.progressTrackIndex = 1
        book.progressTime = 50
        // Completed orderIndex < 1 → 80; + 50
        #expect(book.progressListenedDuration == 130)
    }

    @Test func storeProgressRecapPersistsAllFields() {
        let book = Audiobook(title: "R", folderName: "r", totalDuration: 100)
        book.storeProgressRecap(text: "Body text", headline: "Head line", anchorTrackIndex: 2, anchorTime: 88.5)
        #expect(book.progressRecapText == "Body text")
        #expect(book.progressRecapHeadline == "Head line")
        #expect(book.progressRecapAnchorTrackIndex == 2)
        #expect(book.progressRecapAnchorTime == 88.5)
    }

    @Test func clearProgressRecapNilsAllFields() {
        let book = Audiobook(title: "R", folderName: "r", totalDuration: 100)
        book.storeProgressRecap(text: "x", headline: "h", anchorTrackIndex: 0, anchorTime: 1)
        book.clearProgressRecap()
        #expect(book.progressRecapText == nil)
        #expect(book.progressRecapHeadline == nil)
        #expect(book.progressRecapAnchorTrackIndex == nil)
        #expect(book.progressRecapAnchorTime == nil)
    }

    @Test func discardRecapClearsWhenTrackMismatches() {
        let book = Audiobook(title: "R", folderName: "r", totalDuration: 100)
        book.progressTrackIndex = 1
        book.progressTime = 50
        book.storeProgressRecap(text: "stale", headline: "h", anchorTrackIndex: 0, anchorTime: 50)
        book.discardProgressRecapIfAnchorMismatched()
        #expect(book.progressRecapText == nil)
    }

    @Test func discardRecapClearsWhenTimeMismatches() {
        let book = Audiobook(title: "R", folderName: "r", totalDuration: 100)
        book.progressTrackIndex = 0
        book.progressTime = 200
        book.storeProgressRecap(text: "stale", headline: "h", anchorTrackIndex: 0, anchorTime: 50)
        book.discardProgressRecapIfAnchorMismatched()
        #expect(book.progressRecapText == nil)
    }

    @Test func discardRecapKeepsWhenAnchorMatches() {
        let book = Audiobook(title: "R", folderName: "r", totalDuration: 100)
        book.progressTrackIndex = 0
        book.progressTime = 120
        book.storeProgressRecap(text: "keep", headline: "ok", anchorTrackIndex: 0, anchorTime: 120)
        book.discardProgressRecapIfAnchorMismatched()
        #expect(book.progressRecapText == "keep")
        #expect(book.progressRecapHeadline == "ok")
    }
}
