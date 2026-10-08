# Visual parity fixes, 2026-10-08

Scope: Android player, book detail, EQ, Settings and Done capsules. References
were the paired captures in `/private/tmp/final-visual-report/` and the matching
SwiftUI views. iOS files are unchanged.

- Previous chapter keeps the iOS rule. It is disabled within the first five
  seconds of chapter one and in single-chapter books, and otherwise restarts or
  steps back. Like iOS, a position in a different track from the chapter start
  restarts the current chapter. The earlier capture difference came from the
  two players sitting at different positions, not from a rule difference.
- Change cover is a white 11sp label in a translucent capsule at the cover's
  bottom, with 8dp outer padding and 8dp/4dp inner padding. The cover remains
  130dp square with 20dp corners. Picker, crop, long-press removal and tag remain.
- Size metadata uses a 10dp outline drive instead of Material's stacked storage
  glyph, matching `internaldrive` and Swift's four-point icon/text gap.
- Detail disclosure rows retain inline expansion. Collapsed chevrons point
  right; expanded chevrons point down. Labels use 15sp medium text and compact
  icons. Moment filtering is available in the expanded or empty-results header.
  An absent recap no longer creates an extra inter-item gap.
- EQ and Settings share medium and large detents via a native Material
  BottomSheetScaffold in a modal dialog. The initial sheet occupies 52.5% of
  the window, based on the supplied iOS captures. It can expand or dismiss by
  dragging. The scroll viewport fits the visible detent and reserves navigation
  bar space. Settings also retains 32dp bottom scroll padding.
- EQ uses plain four-dp slider tracks without dots or endpoint stops, and a
  white capsule thumb. Values still snap in one-dB increments and retain native
  Slider progress/accessibility semantics. Zero preamp is the left endpoint.
  Card typography and control heights follow the compact SwiftUI layout.
- EQ bands stay at 60/230/910/3600/14000 Hz, matching `EqualizerSettings.swift`.
- All sheet Done controls share a capsule component. Player chapters, EQ,
  moment editing/filtering and backup use the bordered toolbar capsule.
  Settings, AI Settings and Audiobookshelf Settings use the smaller filled
  capsule from `SettingsSheetHeader`. All existing tags, text and content
  descriptions remain. No E2E selectors needed renaming.

## Validation boundary

Passed checks: `:app:assembleDebug`, `:app:lintDebug`,
`:app:testDebugUnitTest`, `:e2e:assembleDebug`. Final run completed successfully
in 33 seconds, with zero lint issues and 212 host tests passing (before the two reverts above).
`git diff --check` passed.

No emulator was started and no device/E2E journey was run. The supplied captures
were inspected as references; these changes still need the maintainer's fresh
screenshots and runtime checks, especially sheet dragging, system insets,
slider gestures and retained E2E selectors.
