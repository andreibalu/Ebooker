//
//  AudioPlayerManagerRewindTests.swift
//  PagelessTests
//

import AVFoundation
import Foundation
import SwiftData
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

    // Catches: a finished book rewinding on Play. The end-of-chapter sleep timer pauses (stamping the
    // anchor) and then finishes the book, and the anchor used to survive the finish.
    // Catches: finishing a book leaving the "seen playing" stamp, so a route change or call within
    // 3 s reads as audible, pauses the finished book (persist writes isFinished = false) and stamps
    // a break on it.
    @Test func finishingTheBookStopsCountingAsAudible() async {
        let (player, book) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.bookFinishedSink = {}
        player.seedUnitTestPlayingObserved(at: Date().addingTimeInterval(-1))

        player.nextTrack() // last track: finishes the book
        player.pause()

        #expect(!player.hasSmartRewindAnchorForTesting)
        #expect(player.lastAudibleAtForTesting(book.id) == nil)
    }

    @Test func finishingTheBookDropsTheBreakAnchor() async {
        let (player, book) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.bookFinishedSink = {}
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))

        player.nextTrack() // last track: finishes the book

        #expect(book.isFinished)
        #expect(!player.hasSmartRewindAnchorForTesting)
    }

    // Catches: an anchor stamped after the finish (a later pause) still rewinding the finished
    // book from its end.
    @Test func aFinishedBookNeverRewindsOnPlay() async {
        let (player, book) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.bookFinishedSink = {}
        player.nextTrack()
        #expect(book.isFinished)
        let end = player.currentTime
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))

        player.play(reconcileABS: false)

        #expect(player.currentTime == end)
    }

    // Catches: the chapter-sleep-ended item rewinding back into the chapter that ended instead of
    // starting the next file at 0.
    @Test func playAfterChapterSleepEndStartsTheNextFileWithoutRewinding() async {
        let (player, book) = await loadedPlayer(trackCount: 2, trackIndex: 0, time: 59)
        player.applyObservedTime(59) // lands the load's own seek, as the periodic observer would
        player.seedUnitTestChapterSleepEndedCurrentItem()
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))

        player.play(reconcileABS: false)

        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 1, time: 0, autoplay: true
        ))
        #expect(!player.hasSmartRewindAnchorForTesting)
    }

    // MARK: - Fresh loads

    // Catches: a paused fresh load rewinding at load AND leaving a fresh anchor, so the following
    // Play rewinds a second time (or, with the anchor at "now", never measures the real break).
    @Test func pausedFreshLoadDefersTheRewindToPlayAndAppliesItOnce() async {
        let player = makePlayer()
        let book = makeBook(trackCount: 1)
        book.currentTime = 50
        book.lastPlayedAt = Date().addingTimeInterval(-600)

        await player.startPlayback(for: book, autoplay: false)

        #expect(player.currentTime == 50)
        #expect(player.hasSmartRewindAnchorForTesting)
        player.persistence.seekPenaltyRemaining = 0
        player.play(reconcileABS: false)
        #expect(player.currentTime == 20)
        player.pause()
        player.play(reconcileABS: false)
        // The second Play is a quick pause, not another long break.
        #expect(player.currentTime == 20)
    }

    // Catches: an unknown break (no history at all) on a paused load measuring as "now" and
    // skipping the full rewind the policy gives an unmeasurable break.
    @Test func pausedFreshLoadWithUnknownBreakRewindsFullyOnPlay() async {
        let player = makePlayer()
        let book = makeBook(trackCount: 1)
        book.currentTime = 50

        await player.startPlayback(for: book, autoplay: false)
        #expect(player.currentTime == 50)
        player.play(reconcileABS: false)

        #expect(player.currentTime == 20)
    }

    // Catches: the same deferral applying to "Your progress" (`playProgressBookmark`).
    @Test func pausedProgressBookmarkLoadDefersTheRewindToo() async {
        let player = makePlayer()
        let book = makeBook(trackCount: 1)
        book.lastPlayedAt = Date().addingTimeInterval(-600)

        await player.playProgressBookmark(at: 0, in: book, time: 50, autoplay: false)
        #expect(player.currentTime == 50)
        player.play(reconcileABS: false)

        #expect(player.currentTime == 20)
    }

    // Catches: autoplaying fresh loads changing behavior: they still rewind at load and leave no anchor.
    @Test func autoplayingFreshLoadStillRewindsAtLoadAndLeavesNoAnchor() async {
        let player = makePlayer()
        let book = makeBook(trackCount: 1)
        book.currentTime = 50
        book.lastPlayedAt = Date().addingTimeInterval(-600)

        await player.startPlayback(for: book, autoplay: true)

        #expect(player.currentTime == 20)
        #expect(!player.hasSmartRewindAnchorForTesting)
    }

    // MARK: - Play during a paused load

    // Catches: Play pressed while a paused skip back is still loading starting the OLD item
    // (old position briefly audible), after which the commit pauses it and the tap is lost.
    @Test func playDuringAPausedCrossTrackSkipBackPromotesTheLoadToAutoplay() async {
        let (player, book) = await loadedPlayer(trackCount: 2, trackIndex: 1, time: 10)
        player.persistence.seekPenaltyRemaining = 0
        player.skipBackward()
        #expect(player.pendingPlaybackTarget?.autoplay == false)

        player.play(reconcileABS: false)

        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 0, time: 40, autoplay: true
        ))
        #expect(!player.isPlaying) // the old item was not started
        await settle(player)
        #expect(player.currentTrackIndex == 0)
        #expect(player.isPlaying)
    }

    // Catches: a Pause after that Play (still before the commit) not leaving the book paused.
    @Test func pauseAfterPromotingThePausedLoadLeavesItPaused() async {
        let (player, _) = await loadedPlayer(trackCount: 2, trackIndex: 1, time: 10)
        player.skipBackward()
        player.play(reconcileABS: false)

        player.pause()
        await settle(player)
        for _ in 0..<50 { await Task.yield() }

        #expect(player.pendingPlaybackTarget == nil)
        #expect(!player.isPlaying)
        #expect(player.currentTrackIndex == 1)
    }

    // Catches: a pause that only abandons a load stamping the OLD, already-paused book's break as
    // "now" (an hour-old break becoming no break), and its lastAudibleAt too.
    @Test func pausingAnAbandonedLoadKeepsTheExistingBreak() async {
        let (player, book) = await loadedPlayer(trackCount: 2, trackIndex: 0, time: 50)
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-3600))
        player.seedUnitTestPendingPlaybackTarget(PendingPlaybackTarget(
            bookID: book.id, trackIndex: 1, time: 0, autoplay: false
        ))

        player.pause()

        #expect(player.lastAudibleAtForTesting(book.id) == nil)
        player.play(reconcileABS: false)
        #expect(player.currentTime == 20)
    }

    // Catches: a pause that follows AVPlayer pausing itself (interruption, or a stream that was still
    // buffering) deciding the book was not playing, so no break was recorded and the next Play
    // resumed in place with no rewind.
    @Test func pauseJustAfterAVPlayerStoppedItselfStillRecordsTheBreak() async {
        let (player, book) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.seedUnitTestSmartRewindAnchor(nil)
        player.seedUnitTestPlayingObserved(at: Date().addingTimeInterval(-1))

        player.pause()

        #expect(player.hasSmartRewindAnchorForTesting)
        #expect(player.lastAudibleAtForTesting(book.id) != nil)
    }

    // Catches: the widened check making every pause on a long-paused book count as a break start
    // (an hour-old break becoming "now") or a duplicate pause moving a break later.
    @Test func pauseOnABookThatHasBeenSilentForAWhileKeepsTheOldBreak() async {
        let (player, book) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))
        player.seedUnitTestPlayingObserved(at: Date().addingTimeInterval(-60))

        player.pause()
        player.pause()

        #expect(player.lastAudibleAtForTesting(book.id) == nil)
        player.play(reconcileABS: false)
        #expect(player.currentTime == 20)
    }

    // Catches: a second pause right after a real one counting as a fresh stop (the pause's own
    // stamp read as "audible within 3 s") and moving the break's start later.
    @Test func aDuplicatePauseRightAfterARealOneDoesNotMoveTheBreak() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 50)
        player.seedUnitTestPlayingObserved(at: Date().addingTimeInterval(-1))
        player.pause()
        player.seedUnitTestSmartRewindAnchor(Date().addingTimeInterval(-600))

        player.pause()

        player.play(reconcileABS: false)
        #expect(player.currentTime == 20)
    }

    // Catches: a second Play on a downloaded or already-loading book, after Play promoted a paused
    // skip back's load, starting the OLD item (or an ABS reconcile that can override the user's
    // skip) while the promoted load is still pending.
    @Test func aSecondPlayWhileThePromotedLoadIsPendingChangesNothing() async {
        var reconcileCalls = 0
        let player = makePlayer(reconcileABS: { _, _ in
            reconcileCalls += 1
            return true
        })
        let book = makeBook(trackCount: 2, absItemID: "abs-3")
        await player.playTrack(at: 1, in: book, time: 10, autoplay: false)
        player.persistence.seekPenaltyRemaining = 0
        player.skipBackward()
        player.play()
        let promoted = player.pendingPlaybackTarget
        #expect(promoted?.autoplay == true)

        player.play()

        #expect(reconcileCalls == 0)
        #expect(player.pendingPlaybackTarget == promoted)
        #expect(!player.isPlaying)
        await settle(player)
        #expect(player.currentTrackIndex == 0)
        #expect(player.currentTime == 40)
        #expect(reconcileCalls == 0)
    }

    // Catches: a cross-track skip back during Play's in-flight ABS reconcile seeing `hasPlayIntent == false`
    // and committing paused after load() invalidates the reconcile.
    @Test func skipBackDuringPlayABSReconcileKeepsPlayIntentAndAutoplays() async {
        let reconcileGate = RewindTestGate()
        let player = makePlayer(reconcileABS: { _, _ in
            await reconcileGate.wait()
            return false
        })
        let book = makeBook(trackCount: 2, absItemID: "abs-1")
        await player.playTrack(at: 1, in: book, time: 10, autoplay: false)
        player.persistence.seekPenaltyRemaining = 0

        player.play()
        while !reconcileGate.started { await Task.yield() }

        player.skipBackward()
        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 0, time: 40, autoplay: true
        ))

        reconcileGate.release()
        await settle(player)
        #expect(player.currentTrackIndex == 0)
        #expect(player.currentTime == 40)
        #expect(player.isPlaying)
        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    // Catches: Play pressed while a paused cross-track skip back on an ABS book is still pending
    // entering the ABS reconcile branch instead of promoting the pending target, dropping Play.
    @Test func playDuringPausedCrossTrackSkipBackOnABSBookPromotesLoadAndSkipsReconcile() async {
        var reconcileCalls = 0
        let player = makePlayer(reconcileABS: { book, _ in
            reconcileCalls += 1
            book.currentTrackIndex = 1
            book.currentTime = 55
            return true
        })
        let book = makeBook(trackCount: 2, absItemID: "abs-2")
        await player.playTrack(at: 1, in: book, time: 10, autoplay: false)
        player.persistence.seekPenaltyRemaining = 0

        player.skipBackward()
        #expect(player.pendingPlaybackTarget?.autoplay == false)

        player.play()

        #expect(reconcileCalls == 0)
        #expect(player.pendingPlaybackTarget == PendingPlaybackTarget(
            bookID: book.id, trackIndex: 0, time: 40, autoplay: true
        ))
        #expect(!player.isPlaying)
        await settle(player)
        #expect(reconcileCalls == 0)
        #expect(player.currentTrackIndex == 0)
        #expect(player.currentTime == 40)
        #expect(player.isPlaying)
    }

    // Catches: a pause-cancelled navigate() Task whose (bookID, trackIndex, time) matches a later
    // navigate() still entering load() with its stale seekPenaltyOverride (nil -> 180 s).
    @Test func cancelledNavigationTaskWithSameTargetCannotEnterLoadWithStalePenalty() async {
        var loadCallsForTrackZero = 0
        var penaltiesSeenOnLoad: [Double] = []
        var playerRef: AudioPlayerManager?
        let player = makePlayer(onMakeAudioMix: { asset in
            if (asset as? AVURLAsset)?.url.lastPathComponent == "t0.m4a" {
                loadCallsForTrackZero += 1
                if let p = playerRef {
                    penaltiesSeenOnLoad.append(p.persistence.seekPenaltyRemaining)
                }
            }
        })
        playerRef = player
        player.applyPlaybackDefaults(resumeBacktrack: 30, skipBack: 120, skipForward: 30)
        let book = makeBook(trackCount: 2)
        await player.playTrack(at: 1, in: book, time: 2, autoplay: false)
        player.persistence.seekPenaltyRemaining = 0

        // Previous Track queues (0, 0) with seekPenaltyOverride: nil; pause cancels it;
        // Skip Back clamps to (0, 0) with autoplay: false and seekPenaltyOverride: 0.
        player.previousTrack()
        player.pause()
        player.skipBackward()

        await settle(player)
        for _ in 0..<20 { await Task.yield() }

        #expect(loadCallsForTrackZero == 1)
        #expect(penaltiesSeenOnLoad == [0])
        #expect(player.currentTrackIndex == 0)
        #expect(player.currentTime == 0)
        #expect(!player.isPlaying)
        #expect(player.persistence.seekPenaltyRemaining == 0)
    }

    // MARK: - Undo latch

    // Catches: the pill reappearing (and VoiceOver announcing again) once the playhead has been
    // back at the undo point and moved on.
    @Test func theUndoStaysGoneAfterThePlayheadHasBeenBackAtItsPoint() async {
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        let snapshot = player.makeJumpUndoSnapshot()
        player.seek(to: 50)
        player.recordJumpUndo(from: snapshot)
        #expect(player.isJumpUndoVisible)

        player.seek(to: 21.5)
        player.applyObservedTime(21.5) // the periodic observer's tick
        player.seek(to: 40)

        #expect(player.jumpUndo == nil)
        #expect(!player.isJumpUndoVisible)
    }

    // Catches: returning to the undo point while paused (when the periodic time observer isn't
    // ticking) leaving `jumpUndo` alive so a later skip makes the pill reappear.
    @Test func pausedReturnToUndoPointLatchesOnSeekAndNavigate() async {
        // Same-track return via seek (skipBackward while paused)
        let (player, _) = await loadedPlayer(trackCount: 1, trackIndex: 0, time: 20)
        let snapshot = player.makeJumpUndoSnapshot()
        player.seek(to: 50)
        player.recordJumpUndo(from: snapshot)
        #expect(player.isJumpUndoVisible)

        player.skipBackward()
        #expect(player.jumpUndo == nil)
        #expect(!player.isJumpUndoVisible)

        player.skipForward()
        #expect(player.jumpUndo == nil)
        #expect(!player.isJumpUndoVisible)

        // Cross-track return via navigate (skipBackward while paused)
        let (crossPlayer, crossBook) = await loadedPlayer(trackCount: 2, trackIndex: 0, time: 40)
        let crossSnapshot = crossPlayer.makeJumpUndoSnapshot()
        await crossPlayer.playTrack(at: 1, in: crossBook, time: 10, autoplay: false)
        crossPlayer.recordJumpUndo(from: crossSnapshot)
        #expect(crossPlayer.isJumpUndoVisible)

        crossPlayer.skipBackward()
        #expect(crossPlayer.jumpUndo == nil)
        #expect(!crossPlayer.isJumpUndoVisible)
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

    private func makePlayer(
        onMakeAudioMix: (@MainActor (AVAsset) -> Void)? = nil,
        reconcileABS: (@MainActor (Audiobook, ModelContext?) async -> Bool)? = nil
    ) -> AudioPlayerManager {
        var prep = AudioPlayerLoadPreparation(
            isNetworkAvailable: { true },
            makeAudioMix: { asset in
                onMakeAudioMix?(asset)
                return nil
            },
            loadDuration: { _ in CMTime(seconds: 60, preferredTimescale: 600) },
            prepareSeek: { _, _ in true }
        )
        if let reconcileABS {
            prep.reconcileAudiobookshelfBeforeResume = reconcileABS
        }
        let player = AudioPlayerManager(loadPreparation: prep)
        player.applyPlaybackDefaults(resumeBacktrack: 30, skipBack: 30, skipForward: 30)
        return player
    }

    private func loadedPlayer(trackCount: Int, trackIndex: Int, time: Double) async -> (AudioPlayerManager, Audiobook) {
        let player = makePlayer()
        let book = makeBook(trackCount: trackCount)
        await player.playTrack(at: trackIndex, in: book, time: time, autoplay: false)
        player.persistence.seekPenaltyRemaining = 0
        return (player, book)
    }

    private func makeBook(trackCount: Int, trackDuration: Double = 60, absItemID: String? = nil) -> Audiobook {
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
        let book = Audiobook(title: "Rewind", folderName: "rewind", isFreeBook: absItemID == nil, isDownloaded: false, tracks: tracks)
        book.absItemID = absItemID
        return book
    }

    /// Lets a navigate-created load run to its commit.
    private func settle(_ player: AudioPlayerManager) async {
        for _ in 0..<500 where player.pendingPlaybackTarget != nil {
            await Task.yield()
        }
    }
}

@MainActor
private final class RewindTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
