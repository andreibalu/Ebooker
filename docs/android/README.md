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
[Slice 1](slice-1-shell-library-settings.md) adds the shell, local library/card/
detail parity, persistent settings and additive schema v2 on top of the existing
import foundation. Its architecture decisions are recorded there for subsequent
slices. No GitHub issue/PR state was changed during this work.

[E2E and visual checks](e2e-visual-validation-2026-10-06.md) distinguish current
emulator coverage from remaining product/visual and device qualification.
Playback remains unwired; Shelves, activity, onboarding and moment creation
are later slices. Payments, Plus/tips and Apple sync remain excluded.
