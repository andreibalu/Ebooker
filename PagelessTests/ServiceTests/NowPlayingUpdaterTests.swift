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

    @Test func updateMirrorsPlayStateAndRate() {
        let updater = NowPlayingUpdater()
        for isPlaying in [true, false] {
            updater.update(
                audiobook: makeAudiobook(),
                track: makeTrack(),
                currentTime: 30,
                duration: 300,
                playbackRate: 1.5,
                isPlaying: isPlaying
            )
            let rate = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
            #expect(MPNowPlayingInfoCenter.default().playbackState == (isPlaying ? .playing : .paused))
            #expect(rate == (isPlaying ? 1.5 : 0))
        }
    }

    // MARK: - nowPlayingInfo

    @Test func updateSetsTrackAlbumAndArtistOnlyWhenAuthorIsPresent() {
        let updater = NowPlayingUpdater()
        updater.update(
            audiobook: makeAudiobook(title: "My Book", author: "Jane Austen"),
            track: makeTrack(title: "Prologue"),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: true
        )
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Prologue")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "My Book")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "Jane Austen")

        updater.update(
            audiobook: makeAudiobook(author: ""),
            track: makeTrack(),
            currentTime: 0,
            duration: 300,
            playbackRate: 1.0,
            isPlaying: true
        )
        info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyArtist] == nil)
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
