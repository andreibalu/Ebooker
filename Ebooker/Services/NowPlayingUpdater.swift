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
        next: @escaping CommandAction,
        previous: @escaping CommandAction,
        seek: @escaping SeekAction
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { _ in
            play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            pause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { _ in
            next()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { _ in
            previous()
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
