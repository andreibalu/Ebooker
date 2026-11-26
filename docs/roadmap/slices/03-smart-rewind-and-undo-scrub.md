# Slice 03: Smart Rewind, Cross-Track Skip & In-Player Undo Scrub

## Goal
Make everyday playback feel forgiving and effortless: upgrade "On Resume" from once-per-app-launch to true pause-duration Smart Rewind, let skipping/rewinding cross backward across track boundaries, wire up the already-written `jumpToSavedProgressMarker` as an in-player "Undo scrub" recovery chip, and surface whole-book progress context right in the player and mini player.

## Verified Current State
- **Once-per-launch rewind only:** `AudioPlayerManager.swift:136, 330-332, 385-390` gates `resumeBacktrackSeconds` behind `resumeBacktrackAvailableThisLaunch`. Although `pausedAt` is already recorded at `AudioPlayerManager.swift:435`, resuming via `play()` (`396-431`) after a 15-minute pause, phone call / audio interruption (`234-258`), or sleep timer (`778`) never rewinds unless iOS terminated the app.
- **Asymmetric track boundary:** `skipForward()` crosses into the next track (`AudioPlayerManager.swift:693-697`), but `skipBackward()` (`688-691`) and resume backtrack (`331, 387`) clamp at `0:00` instead of crossing into the end of the previous track.
- **Unwired scrub recovery:** `AudioPlayerManager.jumpToSavedProgressMarker(in:)` (`AudioPlayerManager.swift:363-370`) is already implemented (*"Use when the user scrubbed away and wants to snap back"*), with zero callers.
- **Missing player context:** `PlayerView` shows only current track/chapter elapsed & remaining (not overall book `%` or `currentBookRemainingDuration`, already computed at `AudioPlayerManager.swift:542-551`). `ChapterListSheet.swift:64` displays raw unadjusted `chapter.duration`. `MiniPlayerBar.swift:18-25` shows no chapter subtitle on single-file chaptered M4B/ABS books.

## Scope

### 1. True Pause-Duration Smart Rewind & Cross-Track Rewind
- Replace once-per-launch-only gating with pause-duration-aware rewind (honoring `resumeBacktrackSeconds == 0` as strictly disabled):
  - Cold start / first load of a book (`startPlayback`, `playProgressBookmark`): apply full `resumeBacktrackSeconds` (unless ABS adopted newer server progress or book is finished).
  - In-session `play()` after `pausedAt` or audio interruption:
    - Pause `< 30s`: `0s` (instant resume, no annoying jump when pausing to talk).
    - Pause `30s ..< 5m` (or brief interruption): `min(resumeBacktrackSeconds, 10s)` (gentle catch-up).
    - Pause `>= 5m`: full `resumeBacktrackSeconds`.
  - Keep rewind non-destructive to the saved high-water progress marker.
- **Cross-track backward helper:** Implement `rewindPosition(by seconds: Double)` that steps backward across prior tracks (`sortedTracks`) when `currentTime - seconds < 0` and `currentTrackIndex > 0`, used by both `skipBackward()` and Smart Rewind.

### 2. In-Player "Undo Scrub" / "Return to Saved Progress"
- Track the pre-jump `(trackIndex, time)` whenever the user scrubs the timeline or taps a chapter jump in `PlayerView` / `ChapterListSheet`.
- Show a compact, dismissible transient pill in `PlayerView` (e.g., **"Undo jump"** / **"Back to 14:22"** or **"Return to saved progress"** when `persistence.seekPenaltyRemaining > 0` and diverged from `progressTime`) for ~12 seconds after a scrub/jump. Tapping snaps straight back (calling `jumpToSavedProgressMarker` or restoring the pre-scrub position) with light haptic feedback.

### 3. Whole-Book Context, Speed-Adjusted Chapters & Mini-Player Subtitle
- Add a subtle whole-book progress line in `PlayerView` (e.g., `42% · 4h 12m left` using speed-adjusted `currentBookRemainingDuration`) without crowding small screens or Display Zoom.
- Display speed-adjusted chapter durations in `ChapterListSheet.swift:64` (`TimeFormatter.speedAdjustedSeconds(chapter.duration, rate: player.playbackRate)`).
- Update `MiniPlayerBar` secondary line (`miniSecondaryLine`) to show `player.currentChapter?.title` when playing a single-file book that has embedded/ABS sub-track chapters.

## Decision Gate (Step 3)
Run Decision Review on the exact pause-duration thresholds (e.g. `<30s` / `30s–5m` / `>=5m`) and interaction with ABS server-progress reconciliation (`absReconcileAfterPause`) and `PlaybackPersistence` seek penalty.

## Suggested Layer Split
- **Core:** `Pageless/Services/AudioPlayerManager.swift`, `Pageless/Services/PlaybackPersistence.swift`, plus pure rewind-position & pause-tier helper + unit tests in `PagelessTests/`.
- **UI:** `Pageless/Views/PlayerView.swift`, `Pageless/Views/ChapterListSheet.swift`, `Pageless/Views/MiniPlayerBar.swift`.
- **E2E & Docs:** `e2e/tests/player.e2e.ts` (cross-track skip back, undo-scrub chip after scrubber drag/chapter jump, whole-book remaining label, chapter list speed adjustment), `docs/ios/playback.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** Pure tests for pause-duration rewind tiers (respecting `resumeBacktrackSeconds == 0`, `<30s`, `30s–5m`, `>=5m`, ABS adopted skip) and cross-track rewind math across 1-track and multi-track books (including crossing multiple short tracks and clamping at track 0, 0:00).
- **E2E & Visual (`verify-ebooker`):** Drive `PlayerView` with fixture chaptered M4B and multi-track book; scrub forward, verify Undo chip appears and restores position; verify whole-book remaining updates with playback speed; verify `accessibility-layout.e2e.ts` still passes at large text.
- **Docs:** Update `docs/ios/playback.md` and `support.md` (if user-facing On Resume description changes).
