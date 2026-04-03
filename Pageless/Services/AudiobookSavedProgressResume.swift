//
//  AudiobookSavedProgressResume.swift
//  Pageless
//

import Foundation

/// Single source of truth for “start from saved progress marker vs last position” (CarPlay and tests).
enum AudiobookSavedProgressResume {
    enum StartChoice: Equatable {
        /// Same path as the book detail “Your progress” play button (`playProgressBookmark`).
        case useProgressBookmark(trackIndex: Int, time: Double)
        /// Same path as Continue / library resume (`startPlayback`).
        case useStandardStartPlayback
    }

    /// When starting playback from the library with intent to honor the user’s saved progress marker.
    static func startChoice(for audiobook: Audiobook) -> StartChoice {
        if audiobook.isFinished {
            return .useStandardStartPlayback
        }
        if audiobook.hasProgressPosition,
           let idx = audiobook.progressTrackIndex,
           let t = audiobook.progressTime {
            return .useProgressBookmark(trackIndex: idx, time: t)
        }
        return .useStandardStartPlayback
    }
}
