# Unpaged Android planning

The Android Wayfinder map on GitHub Issues is the canonical decision index. Start here: [Unpaged Android: plan the mirror app](https://github.com/andreibalu/Ebooker/issues/49). Its native sub-issues show open decisions and link resolved answers. The Android app mirrors the core iPhone app without payments or Apple-specific sync. Slices 1–6 are merged, and slices 7–10 are in review. Product and architecture decisions remain open in the issue map.

Keep Android implementation under `android/`. Define scoped Android instructions before scaffolding. Existing `Pageless/` code describes iOS behavior; iOS plans and Xcode commands are not Android implementation instructions. Keep Android durable specs here and research in `docs/research/`.

Tracker operations: [GitHub issue tracker](../agents/issue-tracker.md).

## First implementation piece

The initial Android foundation was developed in a separate worktree to preserve unfinished iOS/E2E work from thread `e052ea07-6272-4f2c-a18e-5dbed80a7fc8`, including root `.gitignore`, `Pageless/`, `PagelessTests/`, and `e2e/`. That scaffold did not include playback or AI; later slices added both.

## Native foundation

The isolated Android scaffold is in [`../../android/`](../../android/README.md),
with its own agent instructions and Gradle build. Read that README for setup,
provisional identity/device choices and validation boundaries. Product and
architecture tickets remain the canonical place for decisions.


## Continued implementation

After the foundation, Andrei requested continued Android implementation on
2026-10-06. The first follow-up was [local import and persistent library](local-library.md),
tracked in [#59](https://github.com/andreibalu/Ebooker/issues/59). Work remains
isolated from unfinished iOS/E2E changes. Product and architecture decisions
remain open in the issue map.


## Current stage

The 2026-10-06 shared parity brief authorizes the native mirror build in slices.
Each slice records its architecture decisions. Slices 1–6 are merged. Slices 7–10
and parallel-emulator E2E are in review as stacked PRs #62–#66:

1. [Shell, library and settings](slice-1-shell-library-settings.md): app shell,
   local library/card/detail parity, persistent settings and schema v2.
2. [Playback](slice-2-playback.md): Media3 service playback, full/mini player,
   chapter navigation, durable progress and manual moment creation.
3. [LibriVox Shelves](slice-3-librivox-shelves.md): cached catalog browsing,
   streaming addition, downloads and samples.
4. [Moments and equalizer](slice-4-moments-equalizer.md): moment metadata/edit/
   delete, pinning, filters and live per-book five-band EQ.
5. [Reading activity and onboarding](slice-5-reading-onboarding.md): reading
   sessions, Favorites stats and once-per-install onboarding/reset.
6. [Audiobookshelf source](slice-6-audiobookshelf.md): encrypted server credentials,
   library browsing, authenticated streaming, server progress and library-card fixes.

7. [Android Auto and system integration](slice-7-android-auto.md): MediaLibraryService,
   car browsing/commands, voice search and launcher shortcut (PR #63).
   Real Android Auto rendering is unverified.
8. [Library backup and restore](slice-8-library-backup-restore.md): schema v5,
   Auto Backup metadata allowlist, missing-audio recovery, restore match,
   free-book archival and Backed-up Library (PR #65).
9. [On-device AI](slice-9-on-device-ai.md): Gemini Nano smart moments/recaps and
   optional consented Whisper transcription (PR #66). Physical Nano qualification remains open.
10. [Media gaps and parity review](slice-10-media-parity.md): embedded MP4 chapters,
   durable LibriVox downloads, cover editing, card/rename/settings/report fixes.
   The [45-view audit](parity-audit-2026-10-07.md) identifies slices 7–9 ownership
   separately. This slice does not change the schema (PR #64).

PR #62 covers parallel-emulator E2E.

SQLite schema v3 combines slice 4's moment pin column and slice 5's
`reading_sessions` table in one additive migration. Slice 6 advances it to v4 with nullable ABS identity
and chapter columns. Slice 8 advances it to v5 with `books.is_archived`. Android
uses native notifications, private local storage, manual moments and on-device AI.
Payments and Plus/tips remain excluded. Apple Intelligence and live multi-device
or cross-platform sync are not included. Slice 7 adds Android Auto integration,
but real head-unit rendering remains unverified.

[E2E and visual checks](e2e-visual-validation-2026-10-06.md) and the
[merged E2E fix run](e2e-merged-fix-2026-10-06.md) record emulator coverage,
driver synchronization and visual-review evidence. Emulator tests do not qualify
physical-device behavior. Gemini Nano, real Android Auto head units, Google Drive
backup timing and OEM device transfer remain untested.
