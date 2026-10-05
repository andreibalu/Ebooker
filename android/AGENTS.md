# Android agent instructions

This subtree is the native Android Unpaged app. Root Xcode, SwiftUI, StoreKit,
iCloud and iOS plan instructions do not describe Android build commands or APIs.
Consult the [Android map](https://github.com/andreibalu/Ebooker/issues/49) and
`../docs/android/` before taking a decision or implementing a ticket. Claim the
named ticket first. Preserve other agents' files and the unfinished iOS/E2E work.

- Work under `android/` and `docs/android/` only unless explicitly authorized.
- Use Kotlin and Jetpack Compose; keep the current single `app` module until
  architecture decisions justify adding modules.
- UI name is Unpaged. `dev.unpaged.android.development`, minSdk 26 and the
  placeholder launcher artwork are provisional development choices, not Play
  registration, a supported-phone promise or final branding.
- No purchases, paywalls, Apple sync or replacement cloud backend. Playback,
  imports, network services and local AI are not implemented in the foundation.
- Native iOS code is a behavior reference; iOS implementation tickets are not
  Android instructions. Do not edit `Pageless/`, `PagelessTests/`, `e2e/`, Xcode
  state or release metadata as part of Android work.
- Use the checked-in Gradle wrapper, process-local JDK/SDK variables and the
  commands in README.md. Never install global Gradle or edit shell profiles.
- Keep SDK paths, signing keys, tokens, generated outputs and local.properties
  out of Git. Dependencies must use exact versions; update checksum alongside
  wrapper changes. No automatic license acceptance without user authorization.
- Run `./gradlew --no-daemon :app:assembleDebug :app:lintDebug` for foundation
  changes and inspect lint reports. Add behavior tests as meaningful behavior
  arrives; do not mirror a trivial shell in tests.
- APK assembly and static lint are not launch, UI, device, background playback
  or AI verification. State those limitations in ticket/PR evidence.
