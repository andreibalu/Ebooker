# Unpaged Android development

Native Kotlin/Compose application under `android/app/`. Local audiobook import,
metadata review, schema-v2 persistence, Favorites/Library/Shelves pager, per-tab
sort menus, favorite hearts, detail disclosures and persisted listening/appearance
settings are implemented. Media3 local/remote playback, full player, mini player,
chapters, speed, sleep, progress and manual moment saves are in
[slice 2](../docs/android/slice-2-playback.md). Shelves browses a separately cached
LibriVox catalog with collections, search/filters, samples, streaming addition and
session-owned downloads ([slice 3](../docs/android/slice-3-librivox-shelves.md)).
Manual moment editing/filtering/pinning and per-book five-band Media3 EQ are in
[slice 4](../docs/android/slice-4-moments-equalizer.md), with additive SQLite v3
and compile-only E2E journeys. Audiobookshelf, AI, payments and cloud sync are absent. See [slice 1](../docs/android/slice-1-shell-library-settings.md)
for the migration and next-slice API contract. The [Android map](https://github.com/andreibalu/Ebooker/issues/49)
remains the product/architecture decision index.

## Build and lint

Use an existing JDK 21 and Android SDK with platform 36 and build-tools 36.0.0.
On the current Mac, run from `android/`:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest
```

These exports affect only the current shell. Other machines should substitute
local JDK/SDK paths. Android Studio and an emulator are optional; global Gradle,
NDK and shell-profile edits are unnecessary. First build downloads Gradle and
Maven dependencies into the user's Gradle cache and creates the normal local
Android debug signing key if absent. Never commit that key. SDK license terms
must be accepted by the developer before SDK installation (already accepted by
Andrei for this Mac).

Outputs, intentionally ignored by Git:

- APK: `app/build/outputs/apk/debug/app-debug.apk`
- Lint: `app/build/reports/lint-results-debug.html` and `.xml`
- Tests: `app/build/reports/tests/testDebugUnitTest/index.html`

To install after a physical Android device is connected, USB debugging enabled
and its RSA prompt accepted:

```sh
"$ANDROID_HOME/platform-tools/adb" install -r app/build/outputs/apk/debug/app-debug.apk
"$ANDROID_HOME/platform-tools/adb" shell am start -n dev.unpaged.android.development/dev.unpaged.android.MainActivity
```

Assembly/lint alone do not verify launch, layout, accessibility or runtime behavior.
The original foundation had build/lint evidence only. The local-library follow-up adds emulator E2E coverage below; physical-device qualification is still pending.

## Pinned tooling

| Component | Version |
| --- | --- |
| Gradle wrapper | 8.13 |
| Android Gradle plugin | 8.13.2 |
| Kotlin and Compose compiler plugin | 2.3.21 |
| Compose BOM | 2025.10.01 |
| Activity Compose | 1.11.0 |
| compile/target SDK; build tools | 36; 36.0.0 |
| Java/Kotlin bytecode target | 17 (build host JDK 21) |

These are compatible stable pins, not a claim to use every newest release.
Lint keeps warnings as errors, with only latest-version advisories
(`AndroidGradlePluginVersion`, `GradleDependency`) disabled: toolchain upgrades
should be reviewed together rather than change the reproducible build.
[Kotlin's compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html)
lists Kotlin 2.3.21 support for Gradle 7.6.3–9.3.0 and AGP 8.2.2–9.0.0.
[AGP 8.13 compatibility](https://developer.android.com/build/releases/agp-8-13-0-release-notes)
requires Gradle 8.13 and supports API 36.1; 8.13.2 supports Kotlin 2.3.
The [Compose compiler plugin](https://developer.android.com/jetpack/androidx/releases/compose-kotlin)
is pinned to Kotlin's version; the BOM pins compatible UI library versions.

The official Gradle 8.13 wrapper JAR SHA-256 is
`81a82aaea5abcc8ff68b3dfcb58b3c3c429378efd98e7433460610fecd7ae45f`.
Verify with `shasum -a 256 gradle/wrapper/gradle-wrapper.jar` against
[Gradle's published checksum](https://services.gradle.org/distributions/gradle-8.13-wrapper.jar.sha256).
The distribution checksum is pinned in `gradle-wrapper.properties` and checked
by the wrapper when fetching Gradle. Wrapper scripts/JAR come from the official
[Gradle v8.13.0 source](https://github.com/gradle/gradle/tree/v8.13.0).

## Provisional choices

`dev.unpaged.android.development` is a development application ID. Version
`0.0.1-dev`, minSdk 26, the two-bar placeholder icon and this empty-screen layout
are scaffolding choices. Minimum phone support, final application identity,
release UI and broader feature architecture remain unresolved Wayfinder
decisions. SDK level alone never establishes local-AI availability.

Playback declares INTERNET and foreground media-playback permissions; ACCESS_NETWORK_STATE
supports LibriVox offline detection. API33+ notification permission is optional and
denial never blocks playback. Local imports use the system document
picker and copy audio into private storage; source files are never deleted.
The private SQLite index and owned audio are excluded from backup; uninstalling
Unpaged removes these copies. Import progress survives rotation, but process
death abandons an uncommitted import and startup removes its staging files. No public iOS documentation or App
Store metadata changes belong in this foundation.


## Local library

Choose **Import Audiobook** and select one or more MP3/M4A/M4B/AAC/WAV/OGG/Opus/FLAC
files. The broad document picker permits M4B files with generic provider MIME
types; selected extensions, actual audio tracks and positive durations are
validated before review. Codec/container support still depends on Android's
media stack and needs device fixtures. Import is foreground work: keep Unpaged
open during the copy. Review/edit title and author, then **Save**.
Tap a book to inspect its ordered files; long-press a card → **Delete** confirms removal
of the app's copies, preserving the selected originals. Embedded chapters and
cover artwork extraction are not included in this slice.

Host tests exercise real temporary-file IO, ordering, iOS-compatible sampled
fingerprints, duplicate multiplicity, cancelled/failed copies, commit failure,
removal and restart cleanup. Robolectric tests exercise SQLite reopen, track
ordering, cascade removal and atomic rollback. Robolectric downloads its API28
framework fixture on the first test run; these are host tests, not device tests.
Additional pinned dependencies: Material Icons Extended 1.7.8, Lifecycle 2.9.4, coroutines 1.10.2, JUnit 4.13.2,
Robolectric 4.16. See [slice details](../docs/android/local-library.md).


## Android end-to-end tests

`e2e/` is a separate `com.android.test` driver process using UI Automator. This
lets it force-stop the production app and verify persistence through relaunch.
Release builds have no fixture hooks. Debug builds have a catalog-only fixture entry
point for Shelves. Local-library fixtures are generated real PCM WAV files and a
corrupt MP3, selected through Android's actual Storage Access Framework UI.
Assertions use visible app/picker controls, never database or repository calls.
The Shelves driver uses bundled debug metadata and forced saved-only browsing.
Merged slice runtime checks are recorded in
[the E2E fix run](../docs/android/e2e-merged-fix-2026-10-06.md).

Use a dedicated API35 default ARM64 image, Pixel 7 AVD named `Unpaged_E2E_*`.
Boot it and specify its serial explicitly, with no other Android devices attached:

```sh
export ANDROID_SERIAL=emulator-5580
./tools/run-e2e.sh
```

The script requires the JDK/SDK exports above. It refuses physical devices,
unrelated AVDs, incomplete boot and additional attached devices. Tests clear only
`dev.unpaged.android.development` on this disposable emulator and disable its
animations. Do not use an AVD holding personal app data. The driver also checks
the emulator name before clearing the app. Picker selectors are pinned to the
English API35 default image; alternate OS/provider/locales need their own run.

The runner performs APK assembly, production lint, host tests and
`:e2e:connectedDebugAndroidTest`. It prints its evidence directory containing
JUnit/HTML results, logcat and light/dark screenshots. On test failure it captures
the screen and accessibility hierarchy. Override `E2E_EVIDENCE_DIR` to retain a
specific output directory. Capture files are evidence for human review, not an
automatically passing pixel-diff gate.

See [E2E and visual evidence](../docs/android/e2e-visual-validation-2026-10-06.md)
for executed journeys, screenshot comparisons and remaining parity gaps.
