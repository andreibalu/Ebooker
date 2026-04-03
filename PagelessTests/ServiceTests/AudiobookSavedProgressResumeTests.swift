//
//  AudiobookSavedProgressResumeTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

struct AudiobookSavedProgressResumeTests {
    @Test func finishedBookUsesStandardPlayback() {
        let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
        let book = Audiobook(
            title: "T",
            folderName: "f",
            totalDuration: 100,
            currentTrackIndex: 0,
            currentTime: 40,
            isFinished: true,
            tracks: [track]
        )
        book.progressTrackIndex = 0
        book.progressTime = 10
        #expect(AudiobookSavedProgressResume.startChoice(for: book) == .useStandardStartPlayback)
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

    @Test func noMarkerUsesStandardPlayback() {
        let track = AudioTrack(title: "Ch1", originalFileName: "a.m4a", storedFileName: "a.m4a", orderIndex: 0, duration: 100)
        let book = Audiobook(
            title: "T",
            folderName: "f",
            totalDuration: 100,
            currentTrackIndex: 0,
            currentTime: 55,
            isFinished: false,
            tracks: [track]
        )
        #expect(AudiobookSavedProgressResume.startChoice(for: book) == .useStandardStartPlayback)
    }
}
