# Unpaged Android planning

The Android Wayfinder map on GitHub Issues is the canonical decision index. Start here: [Unpaged Android: plan the mirror app](https://github.com/andreibalu/Ebooker/issues/49). Bookmark that issue; its native sub-issues show open decisions and its Decisions-so-far section links resolved answers. This effort plans a mirror of the core iPhone app without payments or Apple-specific sync; the user subsequently authorized the first implementation piece after AI research completed: an isolated, buildable Kotlin/Compose foundation. Remaining product and architecture decisions stay open.

Keep future Android implementation under `android/`. Define scoped Android instructions before scaffolding. Existing `Pageless/` code describes iOS behavior; iOS plans and Xcode commands are not Android implementation instructions. Keep Android durable specs here and research in `docs/research/`.

Tracker operations: [GitHub issue tracker](../agents/issue-tracker.md).

## First implementation piece

Create the Android foundation in a separate worktree. Preserve the unfinished iOS/E2E work from thread `e052ea07-6272-4f2c-a18e-5dbed80a7fc8`, including root `.gitignore`, `Pageless/`, `PagelessTests/`, and `e2e/`. Use scoped Android instructions, pinned build tooling and actual build evidence; do not treat the scaffold as playback or AI implementation.

## Native foundation

The isolated Android scaffold is in [`../../android/`](../../android/README.md),
with its own agent instructions and Gradle build. Read that README for setup,
provisional identity/device choices and validation boundaries. Product and
architecture tickets remain the canonical place for decisions.


## Continued implementation

After the foundation, Andrei requested continued Android implementation on
2026-10-06. The next bounded slice is [local import and persistent library](local-library.md),
tracked in [#59](https://github.com/andreibalu/Ebooker/issues/59). Work remains
isolated from unfinished iOS/E2E changes. This execution request permits the
slice; it does not close the open mirror-contract, AI-policy, device-support or
broader architecture decisions by assumption.


## Current stage

The 2026-10-06 shared parity brief authorizes the native mirror build in slices.
Each slice records its architecture decisions; all five are merged on one branch:

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

SQLite schema v3 combines slice 4's moment pin column and slice 5's
`reading_sessions` table in one additive migration. Android replacements are
notifications, manual moments and private local storage. Payments, Plus/tips,
Apple Intelligence and Apple sync remain excluded; Audiobookshelf and Android
Auto are not implemented yet.

[E2E and visual checks](e2e-visual-validation-2026-10-06.md) and the
[merged E2E fix run](e2e-merged-fix-2026-10-06.md) record emulator coverage,
driver synchronization and visual-review evidence. Physical-device
qualification remains pending.
