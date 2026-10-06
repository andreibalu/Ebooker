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
