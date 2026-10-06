# Unpaged Android port

> Scope update: the later [Android Wayfinder map](https://github.com/andreibalu/Ebooker/issues/49) supersedes this note’s narrower MVP recommendation. The user wants a mirror of the core iPhone experience, excluding payments and Apple-specific sync. This note records earlier research, not the final feature contract. CLI SDK tools were subsequently installed with explicit license acceptance; initial environment audit below is historical.

Research date: 2026-10-06. Research only; no application changes, builds, account setup or publication. Sources: current repository plus official platform documentation. Recommendations and effort estimates below are engineering judgments, not measured delivery promises.

## Recommendation

Build a separate native Android app in **Kotlin + Jetpack Compose**, using **Media3 ExoPlayer / MediaLibraryService**, **Room**, and local app storage. Keep the existing iOS app. Start with the free player, local import, bookmarks, sleep timer, listening stats, LibriVox and Audiobookshelf. Validate demand before attempting full feature parity. Android is a second product to maintain, not a compilation target for this SwiftUI project.

Compose is Google's modern native UI toolkit. Media3's service architecture supports playback independent of the foreground activity; Room provides SQLite persistence and migrations. [Compose](https://developer.android.com/develop/ui/compose/documentation), [Media3 background playback](https://developer.android.com/media/media3/session/background-playback), [Room](https://developer.android.com/training/data-storage/room)

## What can be reused

The actual Swift sources use AVFoundation, SwiftData, StoreKit, Speech and FoundationModels. Examples: `Pageless/Services/AudioPlayerManager.swift`, `LibraryImportService.swift`, `ReadingSessionRecorder.swift`, `PlusEntitlementStore.swift`; models under `Pageless/Models/`. `AudiobookshelfClient.swift` and `LibriVoxAPIClient.swift` are HTTP clients but still Swift implementations. Most code therefore needs a Kotlin implementation.

Reuse the behavior specifications, API schemas, catalog IDs/collections, translations, icons, design intent, sample media and test scenarios. Port deterministic rules: track ordering, global book positions, book identity/deduplication, stats hour buckets, seek penalties, bookmark timestamps, catalog retry/error classification and quote validation. Current recorder flushes around five minutes, ignores chunks under 30 seconds and snapshots book metadata so deletion does not erase historical stats. Preserve these invariants rather than blindly copying lifecycle hooks.

Important: the working tree currently contains ongoing iOS changes, including `PlusEntitlementStore.swift` and download infrastructure. The supplied AGENTS.md contains older purchase descriptions. Define Android monetization from the shipping product and fresh store data when implementation starts; this note does not assume old IAP descriptions are current.

## Platform options

| Option | Practical reuse here | Maintenance implication | Verdict |
| --- | --- | --- | --- |
| Native Kotlin/Compose | Product rules and assets; rewrite Android source | Two apps, direct control over audio/storage/car behavior | Best first Android release |
| Kotlin Multiplatform with native UIs | New Kotlin domain/network code could later be shared with SwiftUI | Introduces shared build/interoperability and requires moving existing Swift business logic | Reconsider after Android validates demand |
| Flutter or React Native | Requires a new shared UI/domain implementation; existing SwiftUI does not become shared UI | Native audio/service/car/billing bridges still need ownership; migrating iOS adds another large project | Poor first move solely to add Android |

KMP permits selective sharing with native UI; Flutter documents channels for platform-specific code. The recommendation above is an inference from those architectures and this app's heavy platform integration, not a claim that cross-platform audio cannot work. [KMP overview](https://kotlinlang.org/docs/multiplatform/kmp-overview.html), [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)

## Feature mapping and release boundary

| iOS system / feature | Android approach | First release |
| --- | --- | --- |
| AVPlayer + Now Playing | ExoPlayer owned by MediaLibraryService; Compose observes a MediaController | Required |
| Files importer | Storage Access Framework picker; copy selected media into app storage with explicit progress and low-space handling | Required |
| SwiftData books/tracks/moments/sessions/catalog | Room entities/DAOs; DataStore or equivalent for preferences | Required |
| MP3/M4B playback | Media3 MP3/MP4-family playback; verify codec, duration, VBR seeking, tags and embedded chapters with fixtures | Required playback; chapter parity must be proven |
| Manual moments / timer / stats | Kotlin implementations preserving timestamp and wall-clock semantics | Required |
| LibriVox | Same feed contract, collections and identity rules; new durable Android download implementation | Required browsing/streaming; downloads before public launch |
| Audiobookshelf | Same API concepts: login/API key, libraries, streaming, server progress | Required; streaming only initially |
| CarPlay | Android Auto library/session integration and car quality checks | Second milestone, service seam from day one |
| Five-band EQ with preamp and limiter | Android audio processor or device effect implementation | Later; do not promise identical DSP without testing |
| FoundationModels smart save / recap | Capability-gated on-device Android pipeline | Separate experiment |
| iCloud metadata sync | New cross-platform sync design, or ABS progress for ABS books | Exclude iCloud parity |
| StoreKit purchases | Google Play Billing products and entitlement handling | Exclude subscription until Android premium value exists |

Media3 documents MP3, MP4 and M4A container support, with device-dependent sample decoding and some seeking caveats. That does not establish M4B chapter-metadata parity: test real book fixtures before advertising it. SAF grants access to user-selected documents and supports persisted URI permissions; moved/deleted documents can still become inaccessible. Copying imports is the recommended product choice here, matching the iOS ownership model. [Supported formats](https://developer.android.com/media/media3/exoplayer/supported-formats), [SAF](https://developer.android.com/training/data-storage/shared/documents-files)

Media3 foreground playback needs the declared media-playback service type and relevant foreground-service permissions. Notification/session controls and resumption belong in the playback service. Android Auto consumes a browser/library service and session, and has separate driver-distraction quality requirements. Android Automotive OS is a different distribution target; exclude it initially. [Background playback](https://developer.android.com/media/media3/session/background-playback), [Media apps for cars](https://developer.android.com/training/cars/media)

LibriVox exposes public book and track feeds. Audiobookshelf documents libraries, items and user progress. Port from the current client plus server fixtures: its public reference did not establish the newer refresh contract used in this repository, so do not treat that page as comprehensive for token refresh. [LibriVox API](https://librivox.org/api/info), [ABS API](https://api.audiobookshelf.org/)

## Privacy and AI

Keep imported audio and listening history local. No advertising SDK or analytics SDK is needed to build this MVP. Protect ABS credentials with encryption keys in Android Keystore; never store tokens inside persistent track URLs, logs or backups. Preserve server-origin checks, single-flight refresh tied to connection identity and rejection of unsafe redirects. Android network policy needs its own explicit design; do not enable unrestricted cleartext traffic merely to imitate iOS local-network behavior. [Keystore](https://developer.android.com/privacy-and-security/keystore), [Network security configuration](https://developer.android.com/privacy-and-security/security-config)

Apple FoundationModels has no Android implementation. Google's Gemini Nano/AICore powers local ML Kit generation, but availability and capability must be checked on each device. The custom Prompt API is beta without an SLA/deprecation policy. File transcription is a separate problem: ML Kit's Speech Recognition API is alpha, supports file-descriptor audio, and currently requires mono 16-bit PCM at 16 kHz paced in real time; its advanced mode lists select Pixel devices. This makes long audiobook segment analysis a feasibility experiment, not promised launch parity. [Gemini Nano](https://developer.android.com/ai/gemini-nano), [Prompt API](https://developers.google.com/ml-kit/genai/prompt/android), [Speech Recognition API](https://developers.google.com/ml-kit/genai/speech-recognition/android)

The generic platform SpeechRecognizer may send audio to remote servers. A privacy-preserving port must explicitly require supported on-device recognition or leave smart save unavailable; never silently substitute remote recognition. Preserve local quote verification and plain manual bookmarks. [SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)

## Effort and validation

Assumption: one experienced Android developer working substantially full time, access to representative phones and audio fixtures, existing artwork/specs reused, no iOS rewrite, no backend sync or AI in MVP. These are planning ranges, not vendor benchmarks:

1. **1–2 weeks:** feasibility slice: import MP3/M4B, background playback, position restore, file metadata, ABS login/streaming, one catalog response. Test cheap and flagship phones before expanding.
2. **6–10 additional weeks:** library/player UI, bookmarks/timer/stats, complete import/error paths, catalog/downloads/ABS, accessibility and release hardening. **Total roughly 7–12 developer weeks** for the bounded beta; part-time work extends calendar time.
3. **2–4 additional weeks:** Android Auto and broad device QA, assuming a sound media service. EQ and premium billing each need separate scoping. AI/cross-platform sync require discovery before any defensible estimate.

Release evidence must include Bluetooth/headset controls, call interruption/audio focus, screen-off playback, process death/reboot restore, long seek and VBR files, low storage, moved/revoked documents, interrupted downloads, ABS token expiry/server switch/logout, offline transitions, repeat import deduplication and stats after deletion. Emulator UI tests do not prove real phone background or car behavior. At least a Pixel and Samsung phone plus a weaker device is a suggested test matrix, not a Play mandate.

## Google Play path

As checked today, new phone apps must target Android 16/API 36 under the August 31, 2026 requirement. Minimum supported Android is a separate product decision; Android 8/API 26 is a candidate MVP floor, subject to current dependency requirements and device testing. [Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)

Create/verify a Play developer account, choose the permanent application ID, set up signing and upload a signed Android App Bundle. Prepare original Android screenshots/listing, content rating, app access/reviewer instructions (including a safe ABS demo if needed), ads declaration, Data safety and public privacy policy. No account changes were performed. [Play setup](https://support.google.com/googleplay/android-developer/answer/9859152)

Personal accounts created after November 13, 2023 require a closed test with at least 12 testers continuously opted in for 14 days, then an application for production access; elapsed time alone does not guarantee approval. Recruit real audiobook users while building, rather than buying nominal tester participation. Current account type/date is unknown. [Testing requirement](https://support.google.com/googleplay/android-developer/answer/14151465)

Only locally processed data is excluded from collection disclosure, but actual ABS, catalog, purchase and SDK flows need to be assessed; no-tracking does not automatically mean every Data safety answer is "no." Update root public support/privacy/terms and their mirrors when Android behavior and products are implemented, following AGENTS.md. [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)

If premium features are later sold through Play, implement verified purchase state, pending handling, restoration, acknowledgement and consumable handling. StoreKit entitlements are not Play entitlements; shared access across stores would require an explicit account/backend design. Do not sell an Android Plus tier on the strength of iCloud and Apple-only AI. [Play Billing integration](https://developer.android.com/google/play/billing/integrate)

## Next decision

Run the 1–2 week native playback/import/ABS feasibility slice only after implementation authorization. Before committing to the full port, seek real Android demand through an approved waitlist or existing community feedback. A useful gate would be 12–20 people willing to install the beta and use their own books/server; that threshold is a proposed product decision, not proof of market size. The Android port broadens reach but does not solve acquisition by itself.

## Follow-up: fastest route and installed tooling

Read-only machine audit on 2026-10-06: Apple Silicon (`arm64`), Homebrew at `/opt/homebrew/bin/brew`; working Homebrew OpenJDK 17.0.20.1 and 21.0.12.1 are already installed (roughly 304/330 MB). macOS `/usr/bin/java` and `/usr/bin/javac` are launcher stubs; `/usr/libexec/java_home -V` reports no registered runtime. Use an existing JDK by setting `JAVA_HOME` for the build process; do not install another Java runtime or alter global shell configuration merely to fix discovery.

No Android Studio in `/Applications` or `~/Applications`; no SDK in `~/Library/Android/sdk` or Homebrew's customary SDK locations; no `adb`, `sdkmanager`, `emulator` or `gradle` on PATH; no `~/.android`, `~/.gradle` or Gradle wrapper in this repository. Homebrew metadata confirms the Studio, command-line tools and platform-tools casks are not installed. This is a check of known paths/package records, not an exhaustive search of every disk directory. Free space was about **14 GiB at audit time** and can change during cleanup.

Native is the best fit here and probably the fastest way to a dependable Android audiobook player given the existing native iOS app. It is not proven fastest for every demo: Flutter/React Native can produce screens quickly for an experienced developer, but both require new code here and still need background-audio, file and media-session integration. A WebView/PWA sketch is cheaper to demonstrate UI but is not an equivalent reliable local/background/car player. Narrowing the release scope saves more time than swapping UI frameworks. The 7–12 week estimate above includes LibriVox, ABS and stats; a private local-only beta could be smaller (roughly 3–5 developer weeks including the initial feasibility slice, same experience assumptions). That is a planning judgment, not a commitment or published benchmark.

### Install choice

| Setup | What it provides | Space planning |
| --- | --- | --- |
| CLI SDK + existing JDK + physical Android phone | Build/test/install from Codex; no IDE required | Reserve roughly 3–6 GB initially for SDK/build tools/Gradle/dependencies; estimate, not measured |
| CLI SDK + one ARM64 emulator | Automated UI/screenshot testing without a phone | Reserve roughly 8–15 GB initially including image, AVD writable data and caches; estimate, not measured |
| Android Studio + SDK + one emulator | Human IDE, Compose previews, debugger/profiler and device manager | Official Mac minimum 16 GB free; recommended >=32 GB; leave working headroom beyond that |

The official current downloads list a 156.1 MB Mac ARM command-line tools archive versus a 1.5 GB Studio installer; neither number includes installed SDKs, Gradle caches or emulator data. Google's Mac requirements list 8 GB free for Studio alone, 16 GB with emulator, and 32 GB recommended. These are free-space requirements, not a claim that the final installation occupies exactly those amounts. [Downloads](https://developer.android.com/studio), [Mac requirements](https://developer.android.com/studio/install)

**Recommendation now:** finish disk cleanup, install CLI SDK only, reuse Java 21, and use a physical phone if available. If none is available, add exactly one ARM64 emulator/system image. Studio is optional for agent-driven CLI builds and useful later for human inspection. No NDK, standalone Kotlin compiler or Firebase account is needed for the proposed Kotlin MVP. Gradle should be project-pinned via its wrapper, which downloads the required Gradle distribution; a global Homebrew Gradle installation is unnecessary. Choose compatible stable Android Gradle plugin/Kotlin/Compose/Gradle versions when scaffolding rather than mixing latest releases. [Gradle Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html), [Android build JDKs](https://developer.android.com/build/jdks)

### Concrete commands after installation approval

These commands have **not** been executed. They intentionally set process-local environment variables and one explicit SDK root, avoiding duplicate Homebrew/Studio SDK installations:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
brew install --cask android-commandlinetools
sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
sdkmanager --sdk_root="$ANDROID_HOME" --list_installed
```

The cask exposes `sdkmanager`/`avdmanager`; its default root is under `/opt/homebrew/share/android-commandlinetools`, so `--sdk_root` matters. Build Tools 36.0.0 appears in official documentation and current plugin compatibility tables; refresh the package list before executing if availability changes. [Homebrew cask](https://formulae.brew.sh/cask/android-commandlinetools), [sdkmanager](https://developer.android.com/tools/sdkmanager), [Build Tools](https://developer.android.com/tools/releases/build-tools)

Optional emulator setup, after checking the stable package list for the exact available ARM64 image identifier:

```sh
sdkmanager --sdk_root="$ANDROID_HOME" --list
sdkmanager --sdk_root="$ANDROID_HOME" "emulator" "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n Unpaged_API36 -k "system-images;android-36;google_apis;arm64-v8a"
"$ANDROID_HOME/emulator/emulator" -avd Unpaged_API36
"$ANDROID_HOME/platform-tools/adb" devices
```

If using Studio instead, `brew install --cask android-studio` installs the app; then configure the same SDK directory and the desired packages. Do not run both setup paths with their defaults and accidentally maintain two SDK trees. [Homebrew Studio](https://formulae.brew.sh/cask/android-studio), [Emulator CLI](https://developer.android.com/studio/run/emulator-commandline)

The agent can perform downloads, SDK installs, environment configuration, AVD creation and subsequent Gradle builds with the user's installation authorization and required filesystem/network approval (these destinations are outside this repository's writable sandbox). SDK terms require acceptance; do not silently pipe `yes` to licenses without the user's authorization to accept the terms. A connected phone requires the owner to enable developer options/USB debugging and approve the device's RSA prompt; the agent can then use `adb`. Play identity verification, account payment and ownership declarations remain owner actions, separate from local tool installation. [SDK licenses](https://developer.android.com/tools/sdkmanager), [Physical device setup](https://developer.android.com/studio/run/device)
