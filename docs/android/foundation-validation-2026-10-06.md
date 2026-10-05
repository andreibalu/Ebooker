# Android foundation validation — 2026-10-06

Task: [Android: build and validate the native app foundation](https://github.com/andreibalu/Ebooker/issues/57).
Based on published planning commit `620169657f4487dec9c6c01a7301fdc94b8fc597`,
branch `feat/android-foundation`, isolated worktree
`/private/tmp/unpaged-android-foundation`. The main checkout's unfinished iOS/E2E
work from thread `e052ea07-6272-4f2c-a18e-5dbed80a7fc8` was not checked out,
stashed, reset, staged or edited.

## Executed evidence

- Ran the checked-in wrapper with JDK21 and installed SDK36:
  `./gradlew --no-daemon :app:assembleDebug :app:lintDebug`.
  Final result: **BUILD SUCCESSFUL in 9s**, 48 actionable tasks
  (23 executed, 25 up-to-date). Cold compilation had already executed all tasks.
- Lint XML contains **0 issues**. Warnings remain errors except the two
  latest-version advisory detectors documented in `android/README.md`.
  The initial lint run caught absent modern/legacy backup rules; explicit
  exclusions now cover cloud backup and device transfer as well as legacy backup.
- Official Gradle wrapper JAR checksum verified:
  `81a82aaea5abcc8ff68b3dfcb58b3c3c429378efd98e7433460610fecd7ae45f`.
  Gradle's downloaded 8.13 distribution matched its pinned SHA-256:
  `20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78`.
- `aapt2 dump badging` confirms development application ID
  `dev.unpaged.android.development`, minSDK26, targetSDK36, label Unpaged and
  launcher `dev.unpaged.android.MainActivity`. Only AndroidX's signature-protected
  app-private dynamic-receiver permission is present; no internet, microphone,
  media/storage or other Android system permission is requested.
- `apksigner verify --verbose` succeeds with one signer and APK v2 signing.
  This is the normal local debug signature, not a release/Play key.
- APK: `android/app/build/outputs/apk/debug/app-debug.apk`, about 10 MB,
  SHA-256 `e3fa627d05db2c3c049079ba456f3c6548c8eb54d39eaba5f30f17fb7b77c70b`.
  Local debug signing keys and generated artifacts are not committed; debug APK
  byte-for-byte identity is not promised across machines with different keys.
- `git diff --check` passes; Gradle/build caches and APK output are ignored by
  Android-local `.gitignore`. No global Gradle, Android Studio, emulator,
  system image or NDK was installed. Process-local SDK/JDK variables were used.

## Limitations

No emulator or physical-device launch, layout screenshot or accessibility run.
This is an empty Compose library shell, not playback/import/network/AI support.
MinSDK26, development application ID and placeholder icon remain provisional;
other human Wayfinder decisions were not resolved by this task.

The cold build emitted non-fatal notices about SDK XML metadata-version parsing
and leaving `libandroidx.graphics.path.so` debug symbols unstripped without an
NDK. Build and lint completed; these notices are recorded rather than presented
as runtime failures or proof of runtime compatibility.
