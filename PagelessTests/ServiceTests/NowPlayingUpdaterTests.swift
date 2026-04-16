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

    // MARK: - Remote command routing (AirPods double/triple-click)

    /// AirPods double-click fires `nextTrackCommand` and triple-click fires
    /// `previousTrackCommand`. Audiobook apps re-map those to skip forward/backward,
    /// so both commands must be enabled for remote controls to reach the app.
    @Test func configureCommandsEnablesNextAndPreviousTrackForSkipping() {
        let updater = NowPlayingUpdater()
        updater.configureCommands(
            play: {},
            pause: {},
            skipForwardInterval: 30,
            skipForward: {},
            skipBackwardInterval: 30,
            skipBackward: {},
            seek: { _ in },
            supportedPlaybackRates: [1.0, 1.5],
            changePlaybackRate: { _ in }
        )

        let center = MPRemoteCommandCenter.shared()
        #expect(center.nextTrackCommand.isEnabled == true)
        #expect(center.previousTrackCommand.isEnabled == true)
        #expect(center.skipForwardCommand.isEnabled == true)
        #expect(center.skipBackwardCommand.isEnabled == true)
        #expect(center.skipForwardCommand.preferredIntervals.map(\.doubleValue) == [30])
        #expect(center.skipBackwardCommand.preferredIntervals.map(\.doubleValue) == [30])
    }

    @Test func configureCommandsDisablesNextPrevWhenSkipIntervalIsZero() {
        let updater = NowPlayingUpdater()
        updater.configureCommands(
            play: {},
            pause: {},
            skipForwardInterval: 0,
            skipForward: {},
            skipBackwardInterval: 0,
            skipBackward: {},
            seek: { _ in },
            supportedPlaybackRates: [1.0],
            changePlaybackRate: { _ in }
        )

        let center = MPRemoteCommandCenter.shared()
        #expect(center.nextTrackCommand.isEnabled == false)
        #expect(center.previousTrackCommand.isEnabled == false)
    }
}
