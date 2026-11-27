//
//  AudioPlayerManagerRewindTests.swift
//  PagelessTests
//

import AVFoundation
import Foundation
import Testing
@testable import Pageless

/// Manager-level rules E2E can't reach cheaply: which action clears the break anchor, how a
/// rewind treats the seek penalty, what skip back does on a paused book, and the undo-jump
/// record rules. The pure tiers and the walk across tracks are in `SmartRewindPolicyTests` and
/// `RewindPositionTests`.
@MainActor
@Suite(.serialized)
struct AudioPlayerManagerRewindTests {

    // MARK: - Smart Rewind in play()

    // Catches: Smart Rewind not crossing back into the previous track (the old clamp at 0:00),
    // or the cross-track load skipping the penalty override.
    @Test func longBreakRewindCrossesBackIntoThePreviousTrack() async {
        let (player, book) = await loadedPlayer(trackCount: 2, trackIndex: 1, time: 10)
        player.persistence.seekPenaltyRemaining = 0
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))

        player.play(reconcileABS: false)

        // 10 s into track 1, 30 s back: 10 s to the track start, then 20 s into track 0's 60 s.
        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 0, time: 40, autoplay: true
        ))
        #expect(!player.hasSmartRewindAnchorForTesting)
    }

    // Catches: a pause to talk (under 30 s) rewinding, or the anchor surviving a play.
    @Test func shortBreakResumesInPlaceAndConsumesTheAnchor() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 40)
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-5))

        player.play(reconcileABS: false)

        #expect(player.currentTime == 40)
        #expect(player.pendingPlaybackTarget == nil)
        #expect(!player.hasSmartRewindAnchorForTesting)
    }

    // Catches: a rewind that starts a seek penalty (freezing the progress marker for 3 minutes)
    // when progress was saving, or one that drops a penalty already running.
    @Test func rewindKeepsARunningPenaltyAndStartsNone() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.persistence.seekPenaltyRemaining = 0
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))
        player.play(reconcileABS: false)
        #expect(player.currentTime == 20)
        #expect(player.persistence.seekPenaltyRemaining == 0)

        player.pause()
        player.persistence.seekPenaltyRemaining = 40
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))
        player.play(reconcileABS: false)
        #expect(player.currentTime == 0)
        #expect(player.persistence.seekPenaltyRemaining == PlaybackPersistence.progressSeekPenalty)
    }

    // Catches: the user scrubbing while paused and then being rewound from the spot they chose.
    @Test func aUserSeekClearsTheBreak() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))

        player.seek(to: 45)
        player.play(reconcileABS: false)

        #expect(player.currentTime == 45)
    }

    // Catches: a duplicate pause command moving the break's start later, which shortens the
    // measured break and skips a rewind the user should have had.
    @Test func aDuplicatePauseDoesNotMoveTheBreakLater() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        let earlier = Date().addingTimeInterval(-600)
        player.seedUnitTestSmartRewindAnchor(earlier)

        player.pause()

        #expect(player.hasSmartRewindAnchorForTesting)
        player.play(reconcileABS: false)
        #expect(player.currentTime == 20)
    }

    // MARK: - Skip back

    // Catches: skip back clamping at 0:00 of the current track, and a paused book starting to play
    // because track loads always autoplayed.
    @Test func skipBackCrossesTracksAndStaysPausedWhenPaused() async {
        let (player, book) = await loadedPlayer(trackCount: 2, trackIndex: 1, time: 10)
        player.persistence.seekPenaltyRemaining = 0

        player.skipBackward()

        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 0, time: 40, autoplay: false
        ))
        await settle(player)
        #expect(player.currentTrackIndex == 0)
        #expect(player.currentTime == 40)
        #expect(!player.isPlaying)
        // Applied after the commit, not overwritten by the load's own 180 s.
        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    // Catches: two quick taps during a pending cross-track load both stepping from the old
    // position instead of stacking.
    @Test func skipBackTapsDuringAPendingLoadStack() async {
        let (player, book) = await loadedPlayer(trackCount: 3, trackIndex: 2, time: 10)
        player.applyPlaybackDefaults(resumeBacktrack: 30, skipBack: 40, skipForward: 30)

        player.skipBackward()
        player.skipBackward()

        // 10 s into track 2, 40 back: track 1 at 30. The second tap steps from there: track 0 at 50.
        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 0, time: 50, autoplay: false
        ))
    }

    // MARK: - Undo jump

    // Catches: a jump of 5 s or less (a nudge) raising the pill.
    @Test func smallJumpsRecordNoUndo() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        let snapshot = player.makeJumpUndoSnapshot()
        player.seek(to: 25)
        player.recordJumpUndo(from: snapshot)
        #expect(player.jumpUndo == nil)
    }

    // Catches: a second drag replacing the original point, so undo returns to the middle of a
    // scrub instead of where the user started.
    @Test func laterDragsKeepTheOriginalPointAndExtendTheExpiry() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        let first = player.makeJumpUndoSnapshot()
        player.seek(to: 40)
        player.recordJumpUndo(from: first)
        let original = player.jumpUndo
        #expect(original?.time == 20)

        let second = player.makeJumpUndoSnapshot()
        player.seek(to: 55)
        player.recordJumpUndo(from: second)

        #expect(player.jumpUndo?.time == 20)
        #expect(player.jumpUndo?.trackIndex == 0)
        #expect((player.jumpUndo?.expiresAt ?? .distantPast) >= (original?.expiresAt ?? .distantFuture))
    }

    // Catches: the pill staying up once the playhead is back at the undo point.
    @Test func theUndoHidesWhenThePlayheadIsBackWithinTwoSeconds() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        let snapshot = player.makeJumpUndoSnapshot()
        player.seek(to: 50)
        player.recordJumpUndo(from: snapshot)
        #expect(player.isJumpUndoVisible)

        player.seek(to: 21.5)
        #expect(!player.isJumpUndoVisible)
    }

    // Catches: undo leaving the scrub's seek penalty behind, or starting a paused book.
    @Test func undoReturnsToTheSnapshotRestoresThePenaltyAndClears() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        player.persistence.seekPenaltyRemaining = 0
        let snapshot = player.makeJumpUndoSnapshot()
        player.seek(to: 50)
        player.recordJumpUndo(from: snapshot)
        #expect(player.persistence.seekPenaltyRemaining == PlaybackPersistence.progressSeekPenalty)

        player.undoJump()

        #expect(player.currentTime == 20)
        #expect(player.persistence.seekPenaltyRemaining == 0)
        #expect(player.jumpUndo == nil)
        #expect(!player.isPlaying)
    }

    // Catches: a stale pill surviving a deliberate new start of the book.
    @Test func startingPlaybackClearsTheUndo() async {
        let (player, book) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        let snapshot = player.makeJumpUndoSnapshot()
        player.seek(to: 50)
        player.recordJumpUndo(from: snapshot)
        #expect(player.jumpUndo != nil)

        await player.playTrack(at: 0, in: book, time: 0, autoplay: false)

        #expect(player.jumpUndo == nil)
    }

    // MARK: - Whole-book position

    // Catches: using stored durations for the current track (stale until a load commits) or
    // `Audiobook.progress`, which disagree with the live scrubber.
    @Test func bookPositionUsesLiveDurationForTheCurrentTrack() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 3)
        // Stored 60 s each; the live duration of the current (middle) track is 100 s.
        player.seedUnitTestPlaybackState(
            audiobook: book, track: book.sortedTracks[1], trackIndex: 1, currentTime: 40, duration: 100
        )

        let summary = player.bookPositionSummary()
        // total 60 + 100 + 60 = 220; listened 60 + 40 = 100.
        #expect(summary?.remainingSeconds == 120)
        #expect(abs((summary?.fraction ?? 0) - 100.0 / 220.0) < 1e-9)

        let scrubbed = player.bookPositionSummary(currentTrackTimeOverride: 100)
        #expect(scrubbed?.remainingSeconds == 60)
    }

    // Catches: a division by zero or a bogus line for a book with no known durations.
    @Test func bookPositionIsNilWhenTheTotalIsZero() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1, trackDuration: 0)
        player.seedUnitTestPlaybackState(
            audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 0, duration: 0
        )
        #expect(player.bookPositionSummary() == nil)
    }

    // MARK: - Helpers

    private func loadedPlayer(trackCount: Int, trackIndex: Int, time: Double) async -> (AudioPlayerManager, Audiobook) {
        let player = AudioPlayerManager(loadPreparation: AudioPlayerLoadPreparation(
            isNetworkAvailable: { true },
            makeAudioMix: { _ in nil },
            loadDuration: { _ in CMTime(seconds: 60, preferredTimescale: 600) },
            prepareSeek: { _, _ in true }
        ))
        player.applyPlaybackDefaults(resumeBacktrack: 30, skipBack: 30, skipForward: 30)
        let book = makeBook(trackCount: trackCount)
        await player.playTrack(at: trackIndex, in: book, time: time, autoplay: false)
        player.persistence.seekPenaltyRemaining = 0
        return (player, book)
    }

    private func makeBook(trackCount: Int, trackDuration: Double = 60) -> Audiobook {
        let tracks = (0..<trackCount).map { index in
            let track = AudioTrack(
                title: "T\(index)",
                originalFileName: "t\(index).m4a",
                storedFileName: "t\(index).m4a",
                orderIndex: index,
                duration: trackDuration
            )
            track.remoteURLString = "https://example.com/t\(index).m4a"
            return track
        }
        return Audiobook(title: "Rewind", folderName: "rewind", isFreeBook: true, isDownloaded: false, tracks: tracks)
    }

    /// Lets a navigate-created load run to its commit.
    private func settle(_ player: AudioPlayerManager) async {
        for _ in 0..<500 where player.pendingPlaybackTarget != nil {
            await Task.yield()
        }
    }
}
