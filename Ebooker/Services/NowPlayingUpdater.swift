//
//  NowPlayingUpdater.swift
//  Ebooker
//

import MediaPlayer
import UIKit

/// Manages the MPRemoteCommandCenter and MPNowPlayingInfoCenter integration.
struct NowPlayingUpdater {
    typealias CommandAction = () -> Void
    typealias SeekAction = (Double) -> Void

    func configureCommands(
        play: @escaping CommandAction,
        pause: @escaping CommandAction,
        skipForwardInterval: Double,
        skipForward: @escaping CommandAction,
        skipBackwardInterval: Double,
        skipBackward: @escaping CommandAction,
        seek: @escaping SeekAction
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()
        resetCommands(on: commandCenter)

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = skipForwardInterval > 0
        commandCenter.skipBackwardCommand.isEnabled = skipBackwardInterval > 0
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

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

        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            seek(event.positionTime)
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
    }

    func update(
        audiobook: Audiobook,
        track: AudioTrack,
        currentTime: Double,
        duration: Double,
        playbackRate: Double,
        isPlaying: Bool
    ) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyAlbumTitle: audiobook.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0
        ]

        if !audiobook.author.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = audiobook.author
        }

        if let coverArtData = audiobook.coverArtData, let image = UIImage(data: coverArtData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
