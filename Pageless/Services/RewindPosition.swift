//
//  RewindPosition.swift
//  Pageless
//

import Foundation

/// Steps a position backward through a book's tracks, crossing into the end of earlier tracks.
enum RewindPosition {
    /// - Parameters:
    ///   - trackIndex: positional index into `Audiobook.sortedTracks`.
    ///   - time: seconds into that track.
    ///   - seconds: how far to step back. Zero, negative or non-finite leaves the position as is.
    ///   - trackDurations: stored duration of every track, in `sortedTracks` order.
    /// - Returns: the new position. It clamps at the start of the book, and never enters an earlier
    ///   track whose duration is unknown (0 or less): the walk stops at the start of the track it
    ///   was in.
    static func target(
        trackIndex: Int,
        time: Double,
        seconds: Double,
        trackDurations: [Double]
    ) -> (trackIndex: Int, time: Double) {
        let start = time.isFinite ? max(time, 0) : 0
        guard seconds.isFinite, seconds > 0 else { return (trackIndex, start) }
        if start - seconds >= 0 { return (trackIndex, start - seconds) }

        var remaining = seconds - start
        var index = trackIndex
        while index > 0 {
            let previous = index - 1
            guard trackDurations.indices.contains(previous) else { return (index, 0) }
            let length = trackDurations[previous]
            guard length.isFinite, length > 0 else { return (index, 0) }
            if remaining <= length { return (previous, length - remaining) }
            remaining -= length
            index = previous
        }
        return (0, 0)
    }
}
