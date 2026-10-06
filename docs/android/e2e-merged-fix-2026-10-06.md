# Merged shell, playback and Shelves E2E fix — 2026-10-06

Scope: the merged slices 1–3 on the existing branch, using only the already
booted `emulator-5580` (`Unpaged_E2E_API35`). No iOS source, other worktrees,
GitHub state, emulator lifecycle or guard checks were changed.

## Diagnosis and changes

The unchanged merged baseline at `/private/tmp/unpaged-e2efix-baseline`
reproduced all three reported failures and found two Shelves driver failures:
13/18 passed, 5 failed, no skips.

- Save Moment: XML retained `Saved!` after the screenshot showed `Save Moment`.
  The driver now clears UiAutomation accessibility caches before polling
  the tagged action and its current visible label. An initial explicit-label
  approach did not fix the cached hierarchy and was removed.
  Continuous playback events also outlasted the default 10-second idle wait,
  causing fresh queries to miss the two-second Saved! feedback. Configure a
  short idle timeout and poll without an upfront long idle wait. Geometry
  still settles explicitly. Actual saved-moment counts and persistence remain asserted.
- Tracks: the XML and screenshot showed a collapsed disclosure after the tap.
  The driver waits for Compose layout settlement and retries once only if the
  first track did not appear. Ordered visible tracks remain the assertion.
- Invalid audio: the picker exposed `Invalid.mp3` beneath its bottom taskbar.
  File selection now scrolls and checks full visibility before tapping, including
  multi-file selection. The real invalid-media dialog and empty library after
  relaunch remain required; the app's validation was not relaxed.
- Streaming addition: View in Library already selected Library; tapping that
  tab again opened Sort and hid the book from accessibility. Remove that extra
  tap, retaining add, visible Streaming, identity and relaunch checks.
- Genre: Romance lay below the scrollable menu viewport. Reopening the menu
  retained its scroll, hiding All genre. Scroll to both selection and clearing
  options before tapping, refreshing semantics after every swipe; short menus
  need no scrollable node. Clearing filters preserves list scroll, so the driver
  scrolls back to the hero before entering Collections. Retain visible filtered-result checks.
- Search could similarly retain the old tree despite visible matching results.
  Resource-ID/text polling now clears the API33+ accessibility cache on each
  query, including before resolving click geometry. The alternatives journey
  also waits for the detail navigation tag and scrolls its target row fully
  into view before tapping it.

Visual fixes are deliberately narrow: collection count text has an explicit
line height so it fits inside the established card, and skip transport icons
use a numeral-free circular arrow with the configured interval instead of
masking a fixed 30 glyph (which cut through the arrow).

The faster driver also settles between system-picker drawer/breadcrumb/folder
transitions, returns Home before resetting the disposable app, and retries the
fixture activity once only when `am start -W` reports a launch timeout. A full
iteration recorded Android failing to attach the new app process; no app
exception was observed for that launch.

The existing decisions remain: single production app module, SQLite behind
LibraryStore with additive tested migrations, UnpagedPreferences wrapping
SharedPreferences, and Media3 ExoPlayer/MediaSessionService. No new dependencies.

## Validation

First patched full run: 15/18 passed, 3 failed, no skips, evidence
`/private/tmp/unpaged-e2efix-patched1`. Tracks and invalid audio passed; the
remaining player/search cache and reopened-menu failures informed the final
driver changes. Further full/focused iterations exposed transient-feedback,
menu-cache, picker-navigation and launch timing issues documented above.

Final complete run: **18/18 E2E tests passed**, **54/54 host tests passed**,
zero failures/errors/skips and **0 app lint issues**. **BUILD SUCCESSFUL in
9m31s**, with 86 tasks (6 executed, 80 up-to-date). Evidence:
`/private/tmp/unpaged-e2efix-full-verified` (JUnit, HTML, logcat and 35 PNGs).

From `android/`, with process-local JDK21/SDK exports:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
ANDROID_SERIAL=emulator-5580 E2E_EVIDENCE_DIR=/private/tmp/unpaged-e2efix-full-verified ./tools/run-e2e.sh
```

The runner invokes `./gradlew --no-daemon :app:assembleDebug :app:lintDebug
:app:testDebugUnitTest :e2e:connectedDebugAndroidTest` with `e2eApproved=true`.
Host tests/lint were up-to-date in the last run; their current XML reports were
read back separately. E2E ran all 18 tests in one invocation.

All 35 final captures were inspected against the supplied iOS screenshots and
related SwiftUI/theme source. The [regenerated report](visual-evidence/2026-10-06-merged-e2efix/index.html)
contains 17 pairs and 13 unpaired galleries (47 PNGs); every SHA256 was verified.
Generated with:

```sh
python3 android/tools/make-visual-report.py /private/tmp/unpaged-e2efix-full-verified/screenshots docs/android/visual-evidence/ios-reference-1.4.1 docs/android/visual-evidence/2026-10-06-merged-e2efix
```

## Limits

English API35 emulator/provider fixtures qualify these journeys, not physical
phones or live LibriVox downloads/audio. Shelves metadata uses the debug fixture
and offline gate. No payments, Plus, cloud or AI purchase UI was introduced.
Other slices own activity/onboarding and moments/EQ. Fonts, icons, materials,
cover editing and fixture/activity differences remain visible. The shell visual
journey captures zero moments versus the iOS fixture’s two; the playback journey
creates and persists two real moments. Favorites lacks the reference’s activity
card pending the separate stats slice. The dark iOS Shelves chart has Treasure
Island first, whereas the deterministic Android fixture uses the light
reference’s Jane Eyre-first order in both themes. The supplied
26-detail-dark reference is a duplicate Library image; dark player/chapters,
Shelves detail/collection and import review have no matching supplied iOS state.
The report marks these comparisons as unpaired, not pixel-parity evidence.
