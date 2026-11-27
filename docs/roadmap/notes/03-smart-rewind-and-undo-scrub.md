# Slice 03 notes: Smart Rewind, cross-track skip back, Undo jump

Temporary. Fold the durable parts into `docs/ios/playback.md` (and `audiobookshelf.md`) and delete this file before merge.

## Decisions

Adopted after the decision review: Opus 5.5 `high` is the review of record, with Gemini 4 Neon `high` beside it. Each `(review)` tag marks a change one of them asked for.

### Smart Rewind

1. **Tiers.** A pure `SmartRewindPolicy.rewindSeconds(elapsed: TimeInterval?, setting: Double) -> Double`, with its thresholds as constants on the type:
   - under 30 s → 0;
   - 30 s up to 5 min → `min(setting, 10)`;
   - 5 min or more → `setting`;
   - a `setting` of 0 or less → always 0;
   - an elapsed that is nil, negative or not finite (unknown) → the full `setting`.
2. **Two anchors (review).** `lastPlayedAt` is also stamped on resign-active, on seeks and on load commits, so it can't measure a break.
   - **`smartRewindAnchor: Date?`.** Set by `pause()` only when playback was playing or a load was pending, so a duplicate pause command can't move it later. Also set to now after a load that commits with `autoplay: false`.
   - **Clearing the anchor.** A load committing with autoplay clears it, and so does every user positioning: seek, skip, chapter tap, previous/next chapter, previous/next track, and undo. The user picked the spot.
   - **What `play()` does with it.** `play()` consumes the anchor and rewinds by the tier. `pausedAt` keeps its current meaning (the ABS reconcile gate) and is not reused.
   - **`lastAudibleAt: [UUID: Date]`.** In memory only, written by `pause()` and by the periodic time observer while playing.
   - **Fresh loads.** `startPlayback` and `playProgressBookmark` measure elapsed from `lastAudibleAt[book.id]`. On a cold start, with nothing in that map, they fall back to `audiobook.lastPlayedAt`; when that is nil too, the elapsed is unknown, which means a full rewind.
   - **Snapshot timing.** Take the elapsed snapshot before the ABS reconcile `await`.
   - `resumeBacktrackAvailableThisLaunch` is deleted.
3. **Skipped.** These rewind nothing:
   - a book with `isFinished`, on both `startPlayback` and `playProgressBookmark` (review);
   - a fresh load where ABS adopted server progress;
   - an in-session `play()`: read the anchor before the ABS reconcile `Task`. If the reconcile adopts, drop it. If it adopts nothing, apply the tier in the `play(reconcileABS: false)` follow-up (review);
   - the `chapterSleepEndedItem` path. It drops the anchor and starts the next file at 0, so a rewind can't cross back into the chapter that ended (review).
4. **Non-destructive.** A rewind follows `skipBackward()`'s penalty rule: it keeps a running seek penalty and starts none. `load()` arms 180 s unconditionally today, so `PendingPlaybackTarget` (or a load parameter) carries an optional penalty override, applied after commit (review). Cross-track skip back, Smart Rewind and undo all use it. The progress marker never moves backward.
5. **Route change (review).** Observe `AVAudioSession.routeChangeNotification` with `.oldDeviceUnavailable` (headphones removed) while playing and call `pause()`. Today AVPlayer pauses itself and neither the position nor the anchor is saved.

### Cross-track rewind

6. **Walking back.** A pure `RewindPosition.target(trackIndex:time:seconds:trackDurations:) -> (trackIndex: Int, time: Double)` walks back across earlier tracks in `sortedTracks` order and clamps at (0, 0). An earlier track whose duration is 0 or less (unknown) is never entered: the walk stops at `(trackIndex, 0)` of the track it was in (review).
   - **Who uses it.** `skipBackward()` (and so remote skip back, AirPods and CarPlay), Smart Rewind in `play()`, and fresh loads, which compute the target before `load()`.
   - **Where the step starts.** `skipBackward()` steps from `navigationPosition`, not `currentTime`, so taps during a pending load stack (review).
   - **Another track.** A target there goes through `navigate(toTrack:time:)`, which gains an `autoplay` parameter. Skip back and undo pass the current play intent (playing, or a pending autoplay load), so a paused skip back stays paused. Smart Rewind passes `true`.
   - `skipForward` is unchanged.

### Undo jump

7. **State.** It lives on `AudioPlayerManager`: `@Published private(set) var jumpUndo: JumpUndo?`, holding the book id, `trackIndex`, `time`, the chapter index at snapshot, a `seekPenaltyRemaining` snapshot and `expiresAt`. The API is:
   - `func makeJumpUndoSnapshot() -> JumpUndoSnapshot`: `PlayerView` calls it at scrubber drag start (`onEditingChanged(true)`, review), and `ChapterListSheet` calls it before a chapter tap.
   - `func recordJumpUndo(from: JumpUndoSnapshot)`: called after the seek or `playChapter`. It records nothing when the new global position is within 5 s of the snapshot (review). While a `jumpUndo` for the same book is live, it keeps the original point and only extends `expiresAt`, so several drags undo back to where you started.
   - `func undoJump()`: restores the position through the penalty override, autoplays only if playing, and clears the undo.
   - `func dismissJumpUndo()`.
   - `var isJumpUndoVisible: Bool`: false once the playhead is within 2 s of the undo point.
8. **Expiry and clearing.** It expires after 12 s on one cancellable `Task`, replaced on extend. Never clear it inside `load()`, since undo itself loads across tracks. Clear it in `startPlayback`, `playProgressBookmark`, `playTrack`, `restart`, `unloadIfCurrent`, `markCurrentBookFinished`, `setProgressMarker` and the ABS-adopt branch of `play()` (review). Prev/next chapter, skip buttons, lock-screen and CarPlay scrubs record nothing. VoiceOver adjust on `ScrubSlider` gets one snapshot per adjust; the 5 s floor and the keep-the-original rule apply, and only the pill's first appearance is announced.
9. **The pill.**
   - **Copy.** "Back to 14:22". The time is in the scrubber's current scope: relative to the chapter when chapter scope is on, track time otherwise. When the pre-jump chapter differs from the current one it reads "Back to <chapter title> · 14:22", with the title truncated and the time always visible; an empty title falls back to the time alone.
   - **Layout (review).** It is an overlay, or sits in the existing flexible spacer, so it never moves the transport controls; it must fit at 320 pt Display Zoom.
   - **Behavior.** A light haptic on tap, an x to dismiss, a fade in and out, a Dynamic Type cap, identifier `player.undoJump`, and a VoiceOver announcement when it appears.
   - **Dropped from the spec.** The "Return to saved progress" variant. `jumpToSavedProgressMarker` has no callers and is deleted.

### Context lines

10. **Whole-book line.** It sits on its own row under the time labels and reads `42% · 4h 12m left`.
    - **Math.** Positional sums: stored durations of earlier tracks, plus the live `duration` for the current track, plus stored durations of later tracks. It uses the same sums as `currentBookRemainingDuration`, never `Audiobook.progress` (review).
    - **Percent.** Floored, and clamped to 99 until the book is finished.
    - **Remaining.** Speed-adjusted. Under 60 s it reads "< 1m left".
    - **While dragging.** It follows the scrub value.
    - **Hidden** when the total is 0.
    - **Display.** Identifier `player.bookRemaining`, with a Dynamic Type cap like the time labels.
    - **Model.** The manager exposes a computed `bookPositionSummary: (fraction: Double, remainingSeconds: Double)?` (unadjusted seconds; the view adjusts for speed). It also takes an optional override time for the current track, for scrubbing.
11. **Chapter list and mini player.**
    - `ChapterListSheet` and the CarPlay chapter list (`CarPlayCoordinator`) show durations adjusted for speed.
    - **Mini player.** `MiniPlayerBar.miniSecondaryLine` shows the trimmed `currentChapter?.title` when `chapters.count > 1` and the title differs from the book title. This check comes before the `tracks.count > 1` guard (review). Otherwise the existing track rule applies. Identifier `miniPlayer.subtitle`.
12. **Copy.** The Settings "On Resume" caption becomes "Rewind after a break; longer breaks rewind more". The option titles stay and now mean the maximum. The onboarding copy (`OnboardingScenes.swift:501`) is still true and stays.

### Testing and docs

13. **E2E hook.** In DEBUG fixture launches, `-e2e-smart-rewind-elapsed <seconds>` replaces every measured elapsed (anchor and fresh load), the same way `-e2e-sleep-timer-seconds` works. The existing `player.e2e.ts` relaunch resume test uses it (`600` gives the full rewind).
14. **Docs.**
    - `docs/ios/playback.md`: a Smart Rewind and Undo jump section, plus the stale lines.
    - `docs/ios/audiobookshelf.md`: a rewind is reported as progress, and only a rewind past the 30 s threshold moves other devices.
    - `support.md`: an FAQ line, then the mirror Gist.
    - `e2e/COVERAGE.md` and `e2e/README.md` for the hook.
    - The stale comments in `AudioPlayerManager`.
    - No synced schema, privacy or EULA change.

## Layer notes

(Each implementer adds a section below.)

### Core layer

Files: `Services/SmartRewindPolicy.swift`, `Services/RewindPosition.swift`, `Services/JumpUndo.swift` (new), `Services/AudioPlayerManager.swift`, `Services/CarPlayCoordinator.swift` (chapter durations), tests `SmartRewindPolicyTests`, `RewindPositionTests`, `AudioPlayerManagerRewindTests`. No model, schema or `PlaybackPersistence` change.

API (as decided; no label changes):
- `@Published private(set) var jumpUndo: JumpUndo?`, `JumpUndo(bookID, trackIndex, time, chapterIndex: Int?, seekPenaltyRemaining, expiresAt)`.
- `makeJumpUndoSnapshot() -> JumpUndoSnapshot`, `recordJumpUndo(from:)`, `undoJump()`, `dismissJumpUndo()`, `var isJumpUndoVisible: Bool`.
- `bookPositionSummary(currentTrackTimeOverride: Double? = nil) -> (fraction: Double, remainingSeconds: Double)?`. The fraction is clamped to 0...1 and not floored; the view floors it and clamps to 99 until `isFinished`.
- `startPlayback` and `playProgressBookmark` gained a trailing `elapsed: TimeInterval? = nil` (callers that awaited first pass the measured break; nil measures now). Unknown is NaN.
- `PendingPlaybackTarget` gained `var autoplay: Bool = true`.
- Pure types: `SmartRewindPolicy.rewindSeconds(elapsed:setting:)` with `instantResumeBelow`, `gentleBreakBelow`, `gentleRewindCap`; `RewindPosition.target(trackIndex:time:seconds:trackDurations:)`; `JumpUndoPolicy` (lifetime 12 s, 5 s floor, 2 s hide).

Choices the decisions left open:
- **Anchor on non-autoplay loads.** Decision 2 sets the anchor after a load that commits without autoplay, and decision 2 also clears it on every user positioning. A paused skip back or undo across tracks is a non-autoplay load, so it would have re-armed the anchor right after clearing it. `load()` takes `startsRewindBreak` (default true); `navigate()` and the ABS stream recovery pass false, so only fresh loads start a break.
- **Fresh-load penalty.** Fresh loads keep arming the 180 s penalty as before. The override is used by cross-track skip back, Smart Rewind in `play()` and undo only. A same-track rewind uses `seek(applyProgressPenalty:)` with the `skipBackward()` rule.
- **Undo penalty.** Undo restores the penalty from the snapshot (0 if progress was saving), after the commit for a cross-track undo.
- **Duplicate pause.** `lastAudibleAt` follows the same guard as the anchor (only a pause while playing or a load was pending writes it).
- **Route change.** The handler also counts a stop as playback when the book was audible within 3 s, because AVPlayer may already have flipped `isPlaying` by the time the notification runs.
- **`play()` rewind guards.** It rewinds only when not already playing, with a loaded item and no pending load. The elapsed is read at the first `play()` call, before the ABS reconcile `Task`; the follow-up checks the anchor is still set, so a seek during the reconcile cancels the rewind.
- **`skipBackward()`** steps from `navigationPosition`. A same-track step with no pending load still goes straight to `seek(to:applyProgressPenalty:)` (as before, so the existing penalty tests hold); any other case goes through `navigate`.
- **Test seams.** `seedUnitTestSmartRewindAnchor(_:)` and `hasSmartRewindAnchorForTesting`, because the anchor's age can't be set in a unit test otherwise.
- **E2E hook.** `-e2e-smart-rewind-elapsed <seconds>` (DEBUG and `-e2e-fixture` only) replaces the anchor's elapsed and every fresh load's elapsed. With no anchor (the user positioned the book) `play()` still rewinds nothing.

### UI layer

Files: `Pageless/Utilities/TimeFormatter.swift`, `Pageless/Views/PlayerView.swift`, `Pageless/Views/ChapterListSheet.swift`, `Pageless/Views/MiniPlayerBar.swift`, `Pageless/Views/SettingsView.swift`.

Implemented:
- **Whole-book progress line (`TimeFormatter.bookRemainingSummary`, `PlayerView`).** Sits on its own row under the time labels with identifier `player.bookRemaining` and `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`. Follows `scrubValue` while dragging via `player.bookPositionSummary(currentTrackTimeOverride:)`, floors percent and clamps to 99% until `audiobook.isFinished`, speed-adjusts remaining time with `TimeFormatter.speedAdjustedSeconds`, and formats `< 60 s` as `< 1m left`. Hidden when `bookPositionSummary` returns `nil`.
- **Undo jump pill (`PlayerView`).** `ScrubSlider`'s `onEditingChanged` calls `player.makeJumpUndoSnapshot()` on drag start (and on each VoiceOver adjust) and `player.recordJumpUndo(from:)` after `player.seek(to:)` on drag end. Shown when `player.isJumpUndoVisible` in an unclipped `.overlay` on the flexible `Color.clear` spacer (`minHeight: 20`) between `controlsSection` and `quickActionsSection`, so appearing/disappearing never shifts transport controls. Copy reads `Back to <time>` or `Back to <chapter> · <time>` when `undo.chapterIndex != player.currentChapterIndex` and the title is non-empty, using fixed-size prefix/separator/time with tail-truncated chapter title so the time is always visible at 320 pt Display Zoom. Time is chapter-relative when chapter scrubber scope (`activeChapterRange`) is active, track time otherwise. Tap triggers `player.undoJump()` with `.sensoryFeedback(.impact(weight: .light), trigger:)` (`player.undoJump`); `×` triggers `player.dismissJumpUndo()` with `.buttonStyle(.plain)` (`player.undoJump.dismiss`). Dynamic Type capped at `.xxxLarge`; fade transition via `AppMotion.stateChangeAnimation`; VoiceOver `UIAccessibility.post(.announcement)` fires on `false -> true` transitions only.
- **Chapter list (`ChapterListSheet`).** Snapshots before `player.playChapter(chapter)` and calls `player.recordJumpUndo(from:)` after. Chapter durations are speed-adjusted with `TimeFormatter.speedAdjustedSeconds(chapter.duration, rate: player.playbackRate)`.
- **Mini player (`MiniPlayerBar`).** `miniSecondaryLine` checks `player.chapters.count > 1` and trimmed `player.currentChapter?.title` (when non-empty and different from the book title) before the `tracks.count > 1` fallback, with identifier `miniPlayer.subtitle`.
- **Settings (`SettingsView`).** Updated the "On Resume" caption to `"Rewind after a break; longer breaks rewind more"`.
