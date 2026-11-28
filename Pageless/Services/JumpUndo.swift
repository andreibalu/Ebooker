//
//  JumpUndo.swift
//  Pageless
//

import Foundation

/// The point a scrub or chapter jump left, kept briefly so "Back to 14:22" can return to it.
struct JumpUndo: Equatable {
    let bookID: UUID
    let trackIndex: Int
    /// Seconds into `trackIndex`.
    let time: Double
    /// `AudioPlayerManager.currentChapterIndex` when the snapshot was taken.
    let chapterIndex: Int?
    /// The seek penalty before the jump; undo restores it so a jump and its undo leave no trace.
    let seekPenaltyRemaining: Double
    let expiresAt: Date
}

/// Where the player was just before a scrub or chapter jump. Taken before the jump, handed back
/// to `recordJumpUndo(from:)` after it.
struct JumpUndoSnapshot: Equatable {
    let bookID: UUID?
    let trackIndex: Int
    let time: Double
    let chapterIndex: Int?
    let seekPenaltyRemaining: Double
}

/// The pure rules for recording a jump, kept apart so they can be tested without a player.
enum JumpUndoPolicy {
    /// How long the pill stays up. Extended by a further jump.
    static let lifetime: TimeInterval = 12
    /// A jump that ends within this many seconds of where it started records nothing.
    static let minimumJumpDistance: Double = 5
    /// The pill hides once the playhead is back within this many seconds of the undo point.
    static let hideWithin: Double = 2

    static func isWorthRecording(from: Double, to: Double) -> Bool {
        abs(to - from) > minimumJumpDistance
    }

    static func isNearUndoPoint(playhead: Double, undoPoint: Double) -> Bool {
        abs(playhead - undoPoint) <= hideWithin
    }
}
