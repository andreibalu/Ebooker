//
//  NowPlayingUpdaterTests.swift
//  PagelessTests
//

import Foundation
import MediaPlayer
import Testing
@testable import Pageless

/// Tests that NowPlayingUpdater correctly sets MPNowPlayingInfoCenter state,
/// including the playbackState property that Siri uses to route media commands.
@MainActor
struct NowPlayingUpdaterTests {

    // MARK: - Helpers

    private func makeAudiobook(title: String = "Test Book", author: String = "Author") -> Audiobook {
        Audiobook(title: title, author: author, folderName: "test", totalDuration: 600)
    }

    private func makeTrack(title: String = "Chapter 1") -> AudioTrack {
        AudioTrack(title: title, originalFileName: "ch1.mp3", storedFileName: "ch1.mp3", orderIndex: 0, duration: 300)
    }

    // MARK: - playbackState

    @Test func updateSetsPlayingStateWhenIsPlayingTrue() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(),
            track: makeTrack(),
            currentTime: 30,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: true
        )
        #expect(MPNowPlayingInfoCenter.default().playbackState == .playing)
    }

    @Test func updateSetsPausedStateWhenIsPlayingFalse() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(),
            track: makeTrack(),
            currentTime: 30,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: false
        )
        #expect(MPNowPlayingInfoCenter.default().playbackState == .paused)
    }

    @Test func updateTransitionsFromPlayingToPaused() {
        let updater = NowPlayingUpdater()
        let book = makeAudiobook()
        let track = makeTrack()

        updater.update(audiobook: book, track: track, currentTime: 10, duration: 300, playbackRate: 1.0, isPlaying: true)
        #expect(MPNowPlayingInfoCenter.default().playbackState == .playing)

        updater.update(audiobook: book, track: track, currentTime: 10, duration: 300, playbackRate: 1.0, isPlaying: false)
        #expect(MPNowPlayingInfoCenter.default().playbackState == .paused)
    }

    // MARK: - nowPlayingInfo

    @Test func updateSetsZeroPlaybackRateWhenPaused() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(),
            track: makeTrack(),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.5,
            isPlaying: false
        )
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let rate = info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        #expect(rate == 0)
    }

    @Test func updateSetsActualPlaybackRateWhenPlaying() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(),
            track: makeTrack(),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.5,
            isPlaying: true
        )
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let rate = info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        #expect(rate == 1.5)
    }

    @Test func updateSetsTrackAndAlbumTitles() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(title: "My Book"),
            track: makeTrack(title: "Prologue"),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: true
        )
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Prologue")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "My Book")
    }

    @Test func updateOmitsArtistWhenAuthorIsEmpty() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(author: ""),
            track: makeTrack(),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: true
        )
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyArtist] == nil)
    }

    @Test func updateSetsArtistWhenAuthorIsPresent() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(author: "Jane Austen"),
            track: makeTrack(),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: true
        )
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyArtist] as? String == "Jane Austen")
    }
}
