//
//  AudiobookSavedProgressResumeTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct AudiobookSavedProgressResumeTests {
    @Test func finishedOrUnmarkedBookUsesStandardPlayback() {
        func makeBook(isFinished: Bool, marker: (track: Int, time: Double)?) -> Audiobook {
            let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
            let book = Audiobook(
                title: "T",
                folderName: "f",
                totalDuration: 100,
                currentTrackIndex: 0,
                currentTime: 40,
                isFinished: isFinished,
                tracks: [track]
            )
            book.progressTrackIndex = marker?.track
            book.progressTime = marker?.time
            return book
        }

        #expect(AudiobookSavedProgressResume.startChoice(for: makeBook(isFinished: true, marker: (0, 10))) == .useStandardStartPlayback)
        #expect(AudiobookSavedProgressResume.startChoice(for: makeBook(isFinished: false, marker: nil)) == .useStandardStartPlayback)
    }

    @Test func markerSetUsesProgressBookmark() {
        let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
        let book = Audiobook(
            title: "T",
            folderName: "f",
            totalDuration: 100,
            currentTrackIndex: 0,
            currentTime: 99,
            isFinished: false,
            tracks: [track]
        )
        book.progressTrackIndex = 0
        book.progressTime = 42
        #expect(
            AudiobookSavedProgressResume.startChoice(for: book)
                == .useProgressBookmark(trackIndex: 0, time: 42)
        )
    }
}
