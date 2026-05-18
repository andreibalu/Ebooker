//
//  NowPlayingUpdater.swift
//  Pageless
//

import MediaPlayer
import SwiftUI
import UIKit

/// Manages the MPRemoteCommandCenter and MPNowPlayingInfoCenter integration.
struct NowPlayingUpdater {
    // Cache generated artwork by title so we don't re-render every ~1s tick.
    @MainActor private static var generatedArtworkCache: [String: UIImage] = [:]

    typealias CommandAction = () -> Void
    typealias SeekAction = (Double) -> Void

    typealias PlaybackRateAction = (Double) -> Void

    func configureCommands(
        play: @escaping CommandAction,
        pause: @escaping CommandAction,
        skipForwardInterval: Double,
        skipForward: @escaping CommandAction,
        skipBackwardInterval: Double,
        skipBackward: @escaping CommandAction,
        seek: @escaping SeekAction,
        supportedPlaybackRates: [Double],
        changePlaybackRate: @escaping PlaybackRateAction
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()
        resetCommands(on: commandCenter)

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = skipForwardInterval > 0
        commandCenter.skipBackwardCommand.isEnabled = skipBackwardInterval > 0
        // AirPods double/triple-click and similar remote controls trigger next/previous
        // track commands. For an audiobook we re-map those to skip forward/backward so
        // they use the interval from Settings (same seconds as on-screen buttons).
        commandCenter.nextTrackCommand.isEnabled = skipForwardInterval > 0
        commandCenter.previousTrackCommand.isEnabled = skipBackwardInterval > 0

        let rates = supportedPlaybackRates.filter { $0 > 0 }.sorted()
        commandCenter.changePlaybackRateCommand.isEnabled = rates.count > 1
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = rates.map { NSNumber(value: $0) }

        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]

        commandCenter.playCommand.addTarget { _ in
            play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            pause()
            return .success
        }

        commandCenter.skipForwardCommand.addTarget { _ in
            skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.addTarget { _ in
            skipBackward()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { _ in
            skipForward()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { _ in
            skipBackward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            seek(event.positionTime)
            return .success
        }

        commandCenter.changePlaybackRateCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            changePlaybackRate(Double(event.playbackRate))
            return .success
        }
    }

    private func resetCommands(on commandCenter: MPRemoteCommandCenter) {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changePlaybackRateCommand.removeTarget(nil)
    }

    @MainActor
    func update(
        audiobook: Audiobook,
        track: AudioTrack,
        currentTime: Double,
        duration: Double,
        playbackRate: Double,
        isPlaying: Bool
    ) {
        var albumTitle = audiobook.title
        if !audiobook.author.isEmpty {
            albumTitle += " · \(audiobook.author)"
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyAlbumTitle: albumTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate
        ]

        if let coverArtData = audiobook.coverArtData, let image = UIImage(data: coverArtData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else if let generated = generatedArtwork(for: audiobook.title) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: generated.size) { _ in generated }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    @MainActor
    private func generatedArtwork(for title: String) -> UIImage? {
        if let cached = Self.generatedArtworkCache[title] {
            return cached
        }
        guard let image = GeneratedCoverView.renderImage(title: title, side: 600) else {
            return nil
        }
        Self.generatedArtworkCache[title] = image
        return image
    }
}
