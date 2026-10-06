# Android E2E and visual validation — 2026-10-06

Follow-up to [local-library validation](local-library-validation-2026-10-06.md)
on `feat/android-local-library`, draft [PR #60](https://github.com/andreibalu/Ebooker/pull/60).
The implementation stays in the isolated Android worktree. No iOS source,
unfinished iOS E2E work, release metadata or shared simulator data was edited.

## Execution boundary

`android/e2e/` is a separate Android test module so its UI Automator driver
survives a real force-stop of the production app. Assertions observe visible
controls in the app and actual system document picker; there are no app fixture
hooks, test database calls or repository assertions. Generated 8kHz PCM WAV
files exercise Android's real `MediaExtractor`/`MediaMetadataRetriever` path.
`Invalid.mp3` contains text, deliberately failing media parsing.

The guarded runner requires one explicitly selected, booted `Unpaged_E2E_*`
emulator and refuses extra attached Android devices. Instrumentation checks its
approval argument and AVD name before clearing the development app. It changes
animation settings only on this disposable emulator. It retains fixture
originals and collects logcat, JUnit/HTML, screenshots and failure UI hierarchies.
Production still has one app module; the extra module is solely the test driver.

Environment: JDK21, SDK36/build-tools36.0.0, emulator37.2.12, default ARM64 API35
image revision2, Pixel7 AVD `Unpaged_E2E_API35`, serial `emulator-5580`.
Runner/Test JUnit/UI Automator pins: 1.7.0 / 1.3.0 / 2.3.0.

```sh
# From android/, after setting process-local JAVA_HOME and ANDROID_HOME:
ANDROID_SERIAL=emulator-5580 ./tools/run-e2e.sh
```

Full guarded run: **BUILD SUCCESSFUL**, 2m57s, 86 actionable tasks; JUnit
reports **7 E2E tests, zero failures/errors/skips**. After screenshot inspection
found the dark review heading lacked explicit content color, a focused rerun
of the visual journey passed (**1 test**, 1m26s), with APK assembly, host tests
and strict lint repeated. Latest host XML: **16 tests, zero failures/errors/skips**;
latest production lint XML: **zero issues**. No `:e2e:lint` task is claimed.

Host evidence directories: `/private/tmp/unpaged-android-e2e-verified` and
`/private/tmp/unpaged-android-e2e-visual-final`. The report retains empty captures
from the full run and the six refreshed library/detail/review captures from the
focused run. Gradle uninstalls the driver after tests, so captures are copied via
the instrumentation shell into `Download/Unpaged_E2E_Captures` before collection.
The initial capture-loss iteration was corrected rather than counted as visual
verification. The saved report was checked for all 16 PNGs and matching hashes.

Android debug APK SHA256: `0858335ff23d1ca531d53c7e26676b2d81e63290f1d809aa3db9fefb96befe89`.

## Journeys

| Journey | Visible assertions |
| --- | --- |
| Empty library | My Library, empty state; light/dark captures |
| Real multi-file import | Editable title/author; selected 10/2/1 becomes 1/2/10; rotation; force-stop/relaunch retains metadata/tracks |
| Cancellation | Back out of remembered picker folders; Cancel review; relaunch remains empty |
| Duplicate import | Already-in-library error; one persisted book after relaunch |
| Invalid audio | Invalid-media error; no partial book after relaunch |
| Removal | Cancel confirmation preserves book; confirmed removal persists; original imports again through provider |
| Visual fixtures | Matching titles/authors/durations; library/detail/review light/dark captures; import field labels and edits survive rotation |

Initial red header test failed against the old list UI. Picker iterations exposed
remembered directories, a hidden breadcrumb sharing a drawer label, and the
API35 **Select** control. Selectors now target drawer/breadcrumb resource IDs
and resolve fresh nodes for each action. The invalid-file journey found and
fixed media-parser `IOException` being surfaced as a file-copy error. Copy/open
failures remain separate from validation of the completed private copy.

## Visual evidence

[Side-by-side report](visual-evidence/2026-10-06/index.html) contains eight pairs:
empty, populated library, detail and import review, each in light/dark mode.
PNG bytes are unchanged; `sha256.json` records their digests. Generate another
report with `android/tools/make-visual-report.py <android-captures> <ios-captures> <output>`.
This is a human visual check, not an automated pixel-diff gate or full parity pass.

Android fixture metadata matches iOS: E2E Another Book / Another Fixture Author /
5m; E2E The Listening Book / Fixture Author / 10m; E2E Import.wav / 123s.
Android books are genuinely imported from the provider. The iOS reference uses
existing DEBUG fixture support, including its import-source bypass; this does
not qualify the iOS document picker.

The iOS screenshots came from a dedicated iPhone18Pro / iOS27.0 simulator using
the existing debug app **1.4.0 (109)**, rather than rebuilding the dirty iOS tree.
Executable SHA256: `8168a4e3ba23b8b036f4d839b1d9e2dec1ca23da2bbb61398b27a324ac62f038`.
The current iOS `GeneratedCoverView`/theme source was consulted for styles.
This reference is not claimed as a freshly built 1.4.1 or shipping binary.

Aligned for this slice: warm light and charcoal dark surfaces, black/white
primary ink, count badge/header, centered selected-library underline, two-column
rounded cards, stable FNV cover palette, serif cover lettering/wordmark, rounded
detail cards and grouped import review with Details/Imported Files sections.
Small secondary text uses darker light-mode ink for contrast; the review sheet explicitly sets content color so its dark heading stays readable. Import fields keep
accessible Title/Author descriptions after population; saving blocks sheet hiding.

## Remaining parity and qualification

Favorites/Shelves/settings navigation, playback and progress, moments, favorite
hearts, cover editing and storage-size display are absent from the Android
slice. Their controls are not rendered before the corresponding behavior exists.
The empty-state copy describes local import; it cannot advertise unimplemented
catalog browsing. Detail displays Playback unavailable. Payments/Plus/iCloud
remain excluded from Android.

Roboto/Android serif, Material sheet/button rendering, system picker, status and
navigation bars differ from SwiftUI/iOS. Card spacing/rounding/color and title
hierarchy were checked visually; pixel-identical typography and full-app parity
are not achieved. New functional slices need matching iOS states and extended
E2E coverage. Screenshot comparison remains a required human check on UI changes.

This run covers only the English API35 default emulator/provider with WAV and
invalid-MP3 fixtures. Physical phones, other API levels/providers/locales, real
MP3/M4B/AAC/FLAC codec fixtures, TalkBack, large font, storage exhaustion,
background import and playback remain unqualified. Host/Robolectric tests
provide separate repository and SQLite evidence, not handset certification.


## Selected comparisons

| iOS reference | Android current slice |
| --- | --- |
| ![iOS library](visual-evidence/2026-10-06/ios-library-light.png) | ![Android library](visual-evidence/2026-10-06/android-library-light.png) |
| ![iOS import dark](visual-evidence/2026-10-06/ios-review-dark.png) | ![Android import dark](visual-evidence/2026-10-06/android-review-dark.png) |
