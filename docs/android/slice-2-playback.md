# Slice 2 — playback, player and chapters

The 2026-10-06 parity brief authorizes this implementation in the playback
worktree. No shared emulator operations, GitHub writes, iOS edits or Shelves
source edits belong to this slice.

## Implementation and decisions

Single production `app` module, SQLite `LibraryStore` schema v2 retained. No new
columns are required: ordered tracks, local/remote URLs, current position,
last-played time, speed, finish flag, high-water mark and moments already exist.
`setProgressMarker` explicitly permits a lower mark; periodic progress updates
remain monotonic. SQLite tests cover the existing additive v1→v2 migration and
an explicit lower marker surviving reopen.

Media3 ExoPlayer/session **1.8.0** and MediaRouter **1.8.1** are exact pins.
`PlaybackService` owns the single ExoPlayer and media session, automatic media
notification, focus handling and becoming-noisy pause. One process-wide
`PlayerController` publishes state to Compose and operates on that engine.
A retained MediaController connection binds the UI process to the service;
CPU/network wake locks support screen-off listening. Headset/system transport commands use the same engine through a ForwardingPlayer
that maps skip/chapter commands to the iOS rules. A narrowly scoped ExportedService lint suppression is justified
by `onGetSession` authorizing only this application and Android-trusted media
controllers; global lint remains strict. Notification metadata includes
book album title, track display title, author and a generated cover bitmap.
The foreground media-playback, wake-lock and INTERNET permissions are declared;
the optional API33 notification request starts alongside playback and denial
never gates it. Android media-session notifications have an OS permission exemption.
See [Media3 background playback](https://developer.android.com/media/media3/session/background-playback).

The existing `UnpagedPreferences` is the single SharedPreferences wrapper;
resume, skips and moment offsets use the iOS key names and defaults. Continue
backtracks **once per process launch**, clamps within the current file, and
restarts a finished book. Pause/play never applies another backtrack. A load or
scrub imposes 180 seconds of playing wall-clock penalty before automatic marker
advancement. Skips preserve the marker-saving state when already active.
Mark Progress Here confirms and explicitly moves the marker to the current
position, clearing that penalty. Current-position persistence uses the iOS
five-second position delta, with forced pause/track/seek/speed/background/finish
writes. IO writes are ordered on one coroutine worker, independent of UI lifetime.
A force-stop can lose up to the unsaved five-second interval; a visible pause
queues an immediate write. Errors are surfaced instead of silently discarded.

Speeds: 0.8×, 1×, 1.25×, 1.5×, 1.75×, 2×. Sleep: Off, 5/15/30/60 minutes,
using an injected monotonic clock, independent of playback speed. The current
iOS source has no end-of-chapter sleep option. The timer is in-memory and does
not survive process death, matching iOS. Local and token-free remote tracks
share one multi-item queue. A stream with missing duration metadata uses the
engine-discovered duration and saves it back to that track; unknown duration
never erases a restored position during buffering. Media3's exposed ID3 CHAP metadata supplies embedded
markers when present; otherwise every file contributes one chapter. Markers
are sanitized/deduplicated and the first owns the file head. Previous restarts
a chapter after five seconds, otherwise goes to the previous; a sole chapter
disables both navigation buttons. Multi-track file skips clamp backward and
advance to the next file when a forward skip reaches its end.

The full sheet uses the iOS 140pt cover, warm theme, track title/author/File N,
scrubber, transport and action pills. It can be dismissed with the sheet drag
or down chevron. The chapter sheet highlights the current numbered row with
amber and a waveform. Mini player appears below every root tab and detail;
its chapter subtitle is omitted for single-file books. Detail exposes a Player
button once loaded; cards show Playing only during real playback. Save Moment
writes `Saved Moment` at the current file position minus the configured offset,
clamped to zero. Full editing is deferred as authorized. EQ is visibly disabled.
The system output switcher uses the official
[SystemOutputSwitcherDialogController](https://developer.android.com/reference/androidx/mediarouter/app/SystemOutputSwitcherDialogController)
on API30+; an unavailable platform implementation hides its affordance.

## Verification and handoff

Run from `android/` with the brief's process-local JDK21/SDK environment:

```sh
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest :e2e:assembleDebug
```

`e2e` is a `com.android.test` module: **`:e2e:assembleDebug`** builds its driver
APK; it has no `assembleDebugAndroidTest` task. This slice intentionally does
not run `connectedDebugAndroidTest` or `tools/run-e2e.sh` because Shelves shares
the dedicated emulator. Compilation does not establish runtime parity.

Three added UI Automator journeys cover real picker import → playback advances
→ mini player → pause → force-stop/relaunch → Continue/current time; a 30-second
skip, chapter 2, speed persistence; progress confirmation, two saved moments,
sleep selection/cancel, light/dark player/chapter/detail-mini/library-mini
captures, root-tab mini player continuity and single-track navigation rules.
Fixture generator adds E2E Chapter 1/2 WAV filenames to align display titles
with iOS. Existing picker and guarded runner checks are preserved.

After merge the orchestrator must run the guarded suite and inspect captures:

```sh
ANDROID_SERIAL=emulator-5580 ./tools/run-e2e.sh
python3 tools/make-visual-report.py <captures> ../docs/android/visual-evidence/ios-reference-1.4.1 <report> --playback-only
```

Report pairs are `06-player-light`, `07-chapters-light`,
`10-detail-miniplayer-light`, `11-library-miniplayer-light`. Supplied references
have no dark player/chapters/mini-player captures; the dark gallery explicitly
identifies source-derived comparison rather than inventing iOS captures.

Known qualification gaps: no playback runtime, notification/headset/background,
output switcher or screenshot pass is claimed here. Physical phones, streamed
HTTP errors, codecs/long files and actual embedded-chapter containers still need
runtime fixtures. MP4/M4B chapter atoms not exposed by Media3 use file fallback;
full MP4 chapter parsing is not implemented. Android fonts, icons, Material
sheet geometry, shadows and output UI differ from Apple. EQ and moment editing
remain deferred; no pixel-identical visual claim is made before capture review.

Final checks: **BUILD SUCCESSFUL**, 32 seconds, 85 actionable tasks;
**34 host tests, 0 failures/errors/skips**, **0 reported app lint issues**,
and **14 E2E journeys compiled, 0 executed**. Python source compilation checks
passed for both fixture/report scripts; `git diff --check` passed. Initial task-name,
output-switcher API and lint failures were corrected before this final pass.
Ignored local evidence directory: `android/build/reports/playback-slice2/`
(build log, JUnit XML, lint XML/HTML/text and `summary.json`). No screenshot or
runtime E2E evidence was generated. APK SHA256:
`e2d6343620b5cf61d496eb4e3327bf68870170b807bf005f6977c4b1f963e957`.

Commit handoff: `git add` was denied by the filesystem sandbox when creating
`/Users/andreibalu/Developer/Ebooker/.git/worktrees/android-playback/index.lock`.
No commit or push was created. All changes remain in this worktree for the
orchestrator to commit with the required Codex co-author trailer.
