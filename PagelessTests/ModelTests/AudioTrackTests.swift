//
//  AudioTrackTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct AudioTrackTests {
    @Test func initSetsAllProperties() {
        let track = AudioTrack(
            title: "Chapter 1",
            originalFileName: "disk.m4a",
            storedFileName: "uuid-hashed.m4a",
            orderIndex: 3,
            duration: 900
        )
        #expect(track.title == "Chapter 1")
        #expect(track.originalFileName == "disk.m4a")
        #expect(track.storedFileName == "uuid-hashed.m4a")
        #expect(track.orderIndex == 3)
        #expect(track.duration == 900)
    }

    @Test func storedFileNameIsDistinctFromOriginal() {
        let track = AudioTrack(
            title: "T",
            originalFileName: "original.mp3",
            storedFileName: "stored-123.mp3",
            orderIndex: 0,
            duration: 1
        )
        #expect(track.storedFileName != track.originalFileName)
    }

    @Test func orderIndexIsPreserved() {
        let track = AudioTrack(
            title: "T",
            originalFileName: "a",
            storedFileName: "b",
            orderIndex: 17,
            duration: 5
        )
        #expect(track.orderIndex == 17)
    }

    @Test func durationIsPreserved() {
        let track = AudioTrack(
            title: "T",
            originalFileName: "a",
            storedFileName: "b",
            orderIndex: 0,
            duration: 3_600.25
        )
        #expect(track.duration == 3_600.25)
    }

    @Test func audiobookRelationshipDefaultsNil() {
        let track = AudioTrack(
            title: "T",
            originalFileName: "a",
            storedFileName: "b",
            orderIndex: 0,
            duration: 1
        )
        #expect(track.audiobook == nil)
    }
}
