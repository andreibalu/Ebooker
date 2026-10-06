# Unpaged Android foundation

Native Kotlin/Compose application under `android/app/`. This first piece builds
an empty Unpaged library shell; it has no playback, import, network, AI, payments
or sync implementation. The [Android map](https://github.com/andreibalu/Ebooker/issues/49)
remains the product/architecture decision index.

## Build and lint

Use an existing JDK 21 and Android SDK with platform 36 and build-tools 36.0.0.
On the current Mac, run from `android/`:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew --no-daemon :app:assembleDebug :app:lintDebug
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

To install after a physical Android device is connected, USB debugging enabled
and its RSA prompt accepted:

```sh
"$ANDROID_HOME/platform-tools/adb" install -r app/build/outputs/apk/debug/app-debug.apk
"$ANDROID_HOME/platform-tools/adb" shell am start -n dev.unpaged.android.development/dev.unpaged.android.MainActivity
```

Assembly/lint alone do not verify launch, layout, accessibility or runtime behavior.
No emulator or physical-device run was performed for the foundation.

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
release UI, persistence and feature architecture remain unresolved Wayfinder
decisions. SDK level alone never establishes local-AI availability.

No permissions are declared. Backup is disabled until data/secret handling is
specified; there is currently no user data. No public iOS documentation or App
Store metadata changes belong in this foundation.
