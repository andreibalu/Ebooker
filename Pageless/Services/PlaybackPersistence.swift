//
//  PlaybackPersistence.swift
//  Pageless
//

import Foundation
import SwiftData

/// Handles progress tracking and SwiftData persistence for playback state.
@MainActor
final class PlaybackPersistence {
    var lastPersistedTime: Double = -10
    var seekPenaltyRemaining: Double = 0

    static let progressSeekPenalty: Double = 180

    /// Updates the high-water mark if the user has listened past the previous marker
    /// and the seek penalty has been served.
    func updateProgressIfNeeded(
        audiobook: Audiobook,
        currentTrackIndex: Int,
        currentTime: Double,
        duration: Double
    ) {
        guard seekPenaltyRemaining == 0 else { return }

        let currentOverall = audiobook.listenedDuration
        let storedOverall = audiobook.progressListenedDuration

        if currentOverall > storedOverall {
            audiobook.clearProgressRecap()
            audiobook.progressTrackIndex = currentTrackIndex
            audiobook.progressTime = min(currentTime, duration)
            audiobook.progressUpdatedAt = .now
        }
    }

    /// Persists the current playback position to SwiftData.
    /// Only saves when the delta from last persist is >= 5 seconds, unless force is true.
    func persist(
        audiobook: Audiobook,
        trackIndex: Int,
        time: Double,
        duration: Double,
        rate: Double,
        force: Bool,
        context: ModelContext?
    ) {
        audiobook.currentTrackIndex = trackIndex
        audiobook.currentTime = min(time, duration)
        audiobook.lastPlayedAt = .now
        audiobook.playbackRate = rate
        audiobook.isFinished = false

        guard force || abs(audiobook.currentTime - lastPersistedTime) >= 5 else { return }

        do {
            try context?.save()
            lastPersistedTime = audiobook.currentTime
        } catch {
            // Error handled by caller via playerErrorMessage
        }
    }

    /// Marks an audiobook as finished, updating both current position and progress marker.
    func markFinished(
        audiobook: Audiobook,
        trackIndex: Int,
        duration: Double,
        context: ModelContext?
    ) {
        audiobook.clearProgressRecap()
        audiobook.isFinished = true
        audiobook.currentTrackIndex = trackIndex
        audiobook.currentTime = duration
        audiobook.progressTrackIndex = trackIndex
        audiobook.progressTime = duration
        audiobook.progressUpdatedAt = .now

        do {
            try context?.save()
            lastPersistedTime = audiobook.currentTime
        } catch {
            // Error handled by caller via playerErrorMessage
        }
    }
}
