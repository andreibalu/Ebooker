# Slice 10: embedded chapters, durable downloads and parity review

This work is limited to `android/` and `docs/android/`, on the media worktree.
The assigned emulator is `emulator-5580`. No schema migration is needed;
SQLite remains version 4. Chapter caches and cover files live with owned audio.
No Apple source, release metadata, tracker, backend or purchase UI changed.

## Media implementation

`Mp4Chapters` reads Nero `chpl` and referenced QuickTime `text`/`tx3g` chapter
tracks with bounded random-access IO. It handles 32/64-bit chunk offsets,
extended and EOF-sized boxes, constant/per-sample sizes, multiple sample-to-chunk
runs and versioned media headers. Language does not filter chapter tracks,
including `und`. Malformed/unsupported metadata returns no markers and preserves
file/Media3 ID3 fallback. The existing chapter pipeline sanitizes titles/starts,
orders markers, resolves durations and applies chapter navigation consistently.

Import populates a versioned file-local sidecar. Loading an existing local book
reads or regenerates that cache on IO before playback. Cache identity includes
file length and modification time. No audio is rewritten and no audio payload
is loaded into memory by the parser.

LibriVox downloads use unique WorkManager jobs per catalog ID. Navigation and
relaunch observe the same persistent jobs. A foreground `dataSync` notification
shows progress and cancellation. Track partials retain bytes plus an HTTP
validator; resumption uses Range and If-Range. A server ignoring Range restarts
the file. Invalid offsets/lengths never append. Completed tracks survive retries.
Work uses connected-network constraints and exponential backoff starting at
10 seconds, with up to five attempts before a visible failed state.

Files move into the owned UUID directory before promotion through
`LibraryStore`. A restart recovers completed files and the rename-before-index
crash window. Promotion retains identity, favorites, progress, EQ and moments.
Explicit cancellation removes partial staging; OS suspension preserves it.
Android force-stop suspends jobs until the app is reopened. It does not keep a
foreground service alive through force-stop.

The debug fixture permits only the local test server's HTTP audio endpoint.
Release accepts HTTPS LibriVox audio. The fixture activity, intent extras and
bundled catalog are debug-only.

## Parity changes

The [audit](parity-audit-2026-10-07.md) covers all 45 Swift view files, with
402 concrete copy/accessibility occurrences, interaction rows and parallel
ownership. Added/fixed behavior includes card Resume/Favorite/Rename actions,
persisted rename, source removal labels, cover selection/crop/removal and
embedded cover preview, loaded-book-only Player toolbar, Finished summary,
the always-visible empty-moments hint, edit-on-row-tap, Library-detail offline
downloads and Other Recordings, pinned shared download sections, filter-clear
labels, collection footer, Settings source status/reset row order/confirmation,
chapter spacing and reading-report copy/type/clock details. Appearance changes
preserve open chapter/card/cover state.

Covers decode at a bounded size, normalize EXIF orientation, crop with clamped
pan/zoom into 600px squares and save atomically before refreshing visible state.
Library, detail, mini/full player and media metadata use the same owned cover.
LibriVox covers remain generated unless the user selects their own photo.

## Dependency

`androidx.work:work-runtime-ktx:2.10.5` is the only new dependency, pinned for
persistent scheduling, progress observation and foreground workers. This version
contains foreground data-sync timeout fixes. See the
[official release notes](https://developer.android.com/jetpack/androidx/releases/work#2.10.5)
and [foreground work guidance](https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running).

## Verification

On 2026-10-07 the full suite passed on `Unpaged_E2E_API35_A` with this slice
stacked on slice 7: 33 UI Automator tests, plus host tests and lint.
Host tests generate chapter-box fixtures and exercise byte-range interruption,
restart and rejection. UI Automator adds real M4B import/chapter navigation,
rename/context/reset cancellation, photo crop/persistence/removal and throttled
download → force-stop → relaunch → nonzero Range → completion/offline playback.

## PR review regressions

The review fixes merge every staged audio track into the owned book directory
before promotion, including when a cover edit creates that directory during a
download. Moment playback loads local chapter markers and artwork. Successful
rename and cover edits update the active book and queue metadata in place,
preserving playback position and chapters. WorkManager progress looks up titles
only for its book IDs and reuses them across progress updates; library refreshes
follow finished-work changes instead of every byte-progress emission.

Host regressions cover the directory/cover race and missing-track rejection,
moment chapter/artwork loading, active title/artwork edits without reload or
seek, other-book edit isolation, and cached per-work title queries. On
2026-10-07 assembly and lint passed with no lint issues and a fresh full host
run passed 130 tests. The existing four media journeys passed again on the
dedicated API35 emulator. Two strengthened journeys also passed, checking
chapters after replaying a persisted M4B moment and checking mini/full-player
titles after renaming the loaded book. These checks do not establish real
system-notification rendering or physical-device behavior.

## Qualification boundaries

Emulator execution is not physical-phone qualification. Device audio routes,
headset/media buttons, Doze/OEM process policy, reboot recovery, Android 15/16
foreground quotas/timeouts, battery/thermal behavior, large third-party chapter
files, alternate providers/EXIF formats and real LibriVox outages remain unproven.
No live ABS/LibriVox server reliability claim comes from the local fixture.

Android uses Material icons, native fonts, system permissions/output/picker UI
and Compose sheets. Visual review is source/reference comparison, not an
automatic pixel-diff guarantee. The dark iOS detail reference is a duplicate of
Library. Slices 7–9 remain responsible for car/voice/shortcut, sync/cloud/restore/
delete semantics and AI/recaps. Payments and Plus/tips stay excluded.

## Review follow-up

- Now-playing artwork attached to each `MediaItem` is a cached 512px JPEG
  (`ArtworkThumbnail`, at most 150 KB) rather than the full `cover.png`, to keep
  Binder payloads small; `CarArtworkProvider` still serves the full file by URI.
- Download worker: a refused `setForeground` (Android 12+ background retry) no
  longer fails the attempt; only `IOException` is retried.
- `ResumableFile`: a 416 whose total differs from the `.part` length discards the
  partial and validator and restarts from zero once.
- Re-enqueueing a download dismisses earlier finished rows so a stale error
  banner cannot resurface after a cancel.
- `chpl` parse failures fall through to the QuickTime chapter track; version-0
  `chpl` accepts ffmpeg's four reserved bytes as well as none. Chapter cache titles
  are truncated to the `writeUTF` limit and the temp file is removed on failure.
- "Remove cover" is hidden for Audiobookshelf books (the server cover is the only copy).
