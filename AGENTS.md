# AGENTS.md

Instructions for coding agents in this repo. `CLAUDE.md` imports this file.

## The app

Unpaged is an audiobook player for iPhone, with a native Android port. Three names are historical layers, and each stays where it is:

- **Unpaged** is the App Store and home-screen name. All new user-facing copy says "Unpaged".
- **Pageless** is the Xcode scheme, the source folder prefix (`Pageless/`, `PagelessTests/`, …) and the bundle id prefix `andreibaludev.Pageless`.
- **Ebooker** is the GitHub repository.

The marketing version lives in `VERSION` and in `MARKETING_VERSION` in `project.pbxproj`. Read it there when it matters.

## Where to start

Read the matching file before changing anything in its area:

- Android (`android/`): `android/AGENTS.md`. The iOS sections below cover the Apple app, and the iOS code is Android's behavior spec.
- An iOS feature: its reference under "Feature references" below.
- A release, an App Store Connect upload or an Xcode Cloud build: `docs/ios/release.md`.
- Marketing site (`site/`): `site/README.md`.
- E2E suite (`e2e/`): `e2e/README.md`. Scope and latest results are in `e2e/COVERAGE.md`.
- App Store performance (downloads, sales, subscriptions, ASO): pull App Store Connect data with the `app-store-connect-analytics` plugin when it is installed. Bundle id and SKU: `andreibaludev.Pageless`.
- Issues and Wayfinder maps: `docs/agents/issue-tracker.md`.

## Hard rules

- **The repo is public.** API key ids, issuer ids, `.p8` contents, signing files and tokens live outside it (`~/.appstoreconnect/` and similar). Keep every credential out of commits, logs and PR text.
- **Apple frameworks only.** The iOS app links no third-party package. Build features from system frameworks.
- **Xcode Cloud builds run only when the owner asks.** Pushes start nothing. `docs/ios/release.md` has the script.
- **Public docs follow the app.** `support.md`, `privacy-policy.md` and `EULA.md` are the source for the App Store support, privacy and terms pages. The site renders them at `/support/`, `/privacy/` and `/terms/`, and public GitHub Gists mirror them. Update the source in the same commit, then the matching Gist. Each kind of change touches these pages:
  - Permissions (`NS*UsageDescription` in `Info.plist`): support and privacy.
  - Network behavior, third-party services, collected data: privacy.
  - AI features, purchase terms, trials: all three. EULA §3 holds the purchase terms.
  - Minimum iOS, supported devices, new user-visible features: support.
  - Contact email or developer name: all three, spelled "Andrei Baluta" everywhere.

## Build & Run

iOS builds and tests run only on macOS with Xcode, which means the owner's Mac or Xcode Cloud on request. Read tool and runtime versions from the machine (`xcodebuild -version`, `xcrun simctl list runtimes`). Nothing iOS builds or runs on a Linux host such as a cloud session. Verify by reading code there, and say in the handoff what you could not run.

Build and test with `xcodebuild` through `Bash`:

```bash
xcodebuild -project Pageless.xcodeproj -scheme Pageless \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -configuration Debug -derivedDataPath <scratch>/dd build
```

Swap `build` for `test -parallel-testing-enabled NO`. `xcodebuild -showdestinations -project Pageless.xcodeproj -scheme Pageless` lists valid simulator and device ids. Always pass a `-derivedDataPath` inside your scratch directory so runs don't share DerivedData. A clean build takes minutes, so run it in the background and tail the log.

Use a physical iPhone only for what a simulator can't show: background audio, CarPlay, StoreKit against a sandbox account, and on-device Apple Intelligence.

### Simulator

Drive the simulator with `mcp__Claude_Code_iOS_Simulator__control` (`attach`, `screenshot`, `tap`, `swipe`, `text`) and `xcrun simctl`.

```bash
xcrun simctl list devices available          # pick a udid every run
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid> -b            # wait until booted
xcrun simctl install <udid> <path>/Pageless.app
xcrun simctl launch  <udid> andreibaludev.Pageless
xcrun simctl io <udid> screenshot shot.png   # then open the png
```

- Look up the udid each run and pass it to every command and MCP action. With two devices booted, `booted` picks one without telling you.
- Simulators run headless, so no Simulator window is needed.
- The Xcode developer directory is already configured. Diagnose tool errors without changing `xcode-select`.
- Call `attach` before building. It opens the owner's panel and fails harmlessly when nothing is booted. Coordinates are device points from the top left.
- The first MCP action on a new device raises an access request the owner must answer. With nobody there to answer, capture with `simctl io` instead.
- Wait at least a second after an action before capturing. Transitions animate, and a frame with two screens blended was captured too early.
- Open and look at an image before citing it as visual proof.
- Useful extras: `simctl ui <udid> appearance dark|light`, `simctl status_bar <udid> override --time 9:41`, `simctl privacy <udid> grant microphone andreibaludev.Pageless`, and `simctl uninstall` for a clean-install or onboarding run.
- The runtime decides what AI code runs. Below iOS 26 a run exercises the `Unavailable…` fallbacks, iOS 26 and later the real `FoundationModels` path, and iOS 27 adds its own error handling (`FoundationModelGeneration`). The simulator's model also needs Apple Intelligence enabled on the host Mac. Without it, a run counts only as non-AI regression coverage.

## Architecture

Lightweight MVVM with protocol-typed services. The source tree shows what exists. These are the conventions it can't show.

- **Targets follow folders.** `Pageless/`, `PagelessTests/`, `PagelessUITests/` and `PagelessDownloadActivity/` are Xcode synchronized folders. A file added there joins its target with no `project.pbxproj` edit, and a non-code file ships in the bundle, so keep docs and scratch files out of them. The widget extension compiles its own folder plus the few app files the pbxproj names explicitly (such as `DownloadActivityAttributes.swift`).
- **Views** own `@Query`, `@AppStorage` and UI state, and create view models with `@State`.
- **View models** are `@MainActor @Observable` classes. Services arrive through the initializer as protocol types with concrete defaults, so a caller passes only the subject (an audiobook, an item). Pass `modelContext` in explicitly.
- **Services** without long-lived state are `struct`s behind protocols, or `enum`s of static functions (import, catalog, sync). Services that own long-lived state (playback, downloads, accounts, entitlements, network, the widget snapshot) are singletons (`static let shared`) or environment objects. Reuse them before adding another.
- **`AudioPlayerManager`** owns playback state and is injected with `@EnvironmentObject`. Its `equalizer` is a separate environment object, so EQ views bind without the player.
- **Navigation stays in SwiftUI views.** There are no navigation coordinators or DI containers. `CarPlayCoordinator` exists because CarPlay templates aren't SwiftUI.
- **Library state** comes from computed properties on `Audiobook` (`isStreamingOnly`, `isCloudOnlyOrphan`, `isInActiveLibrary`, `isArchived`). Use them instead of combining raw flags, and check `isDownloaded` before touching a book's files.
- **Covers.** Every cover view falls back to `GeneratedCoverView` when `coverArtData` is nil or unreadable. System surfaces use `GeneratedCoverView.renderImage(title:side:)`.
- **Settings** are `@AppStorage` string keys written at each use site, with option enums and raw values in `Models/PlaybackSettings.swift`. Search for a key's string before renaming it, because every site must match.
- **Appearance** goes through `.appAppearance(_:)`, which sets `overrideUserInterfaceStyle` on the scene's windows so sheets and covers follow. `.preferredColorScheme` can't return to the system scheme until relaunch.
- **Large text and Button Shapes.** Root chrome must stay usable at accessibility text sizes with Button Shapes and Bold Text on, and at Display Zoom's 320pt width. A row with a title, a `Spacer` and fixed-size buttons gives the title `lineLimit(1)` and layout priority, so the title never wraps one letter per line. The library header drops its title through `ViewThatFits` when the row runs out of room. Chrome with fixed geometry (library header, tab picker, section headings, fixed-width cards, button rows) caps Dynamic Type with `.dynamicTypeSize(...)`. Icon buttons that draw their own card use `.buttonStyle(.plain)`, or Button Shapes draws a second pill around them. Rows of menus that can outgrow the width scroll horizontally to the screen edge. `e2e/tests/accessibility-layout.e2e.ts` covers this.
- **Brand accent** is `Color.amber` (`Utilities/Color+Theme.swift`). The asset catalog's AccentColor is black and white.
- **Security-scoped files.** Every `startAccessingSecurityScopedResource` has a matching release path (see `LibraryViewModel.releaseSecurityScopedAccess()`).
- **Completion-handler APIs** (Speech) bridge with `withCheckedContinuation` / `withCheckedThrowingContinuation`.

## Platform gates

- **iOS version.** The deployment target is below iOS 26 (`IPHONEOS_DEPLOYMENT_TARGET`), and `FoundationModels` and `SpeechAnalyzer` need 26. Reference those symbols only inside `@available(iOS 26, *)` types or `if #available(iOS 26, *)` blocks. Shared AI result and error types live in `Services/Protocols/`, so older-iOS callers, `Unavailable…` fallbacks and mocks compile without gates. `AppleIntelligenceCapability` decides whether AI surfaces render.
- **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`).
- **Permissions.** The onboarding Permissions scene is the one place the app asks up front. CarPlay can't show a permission prompt, so a feature reachable only from CarPlay checks status and explains instead of asking. The lazy speech request in the transcription fallback stays as the safety net.
- **ATS.** `NSAllowsArbitraryLoads` lets plain-http Audiobookshelf servers work on LAN and VPN. iOS ignores it when `NSAllowsLocalNetworking`, `NSAllowsArbitraryLoadsForMedia` or `NSAllowsArbitraryLoadsInWebContent` is present, so it stays the only ATS key (`docs/ios/audiobookshelf.md`).

## Data layer

SwiftData, with one `ModelContainer` built in `AppDelegate` from two configurations. `"synced"` holds the user's library and goes to the CloudKit private database when sync is on. `"local"` holds the LibriVox catalog cache and never syncs. `AppDelegate` lists which models each holds.

- **Synced models stay CloudKit-shaped.** They need explicit relationship inverses and no `@Attribute(.unique)`. Only local-store models may use `.unique`. `SchemaCompatibilityTests` validates the synced schema against CloudKit.
- **Columns added after launch** are optional private backing fields (`_isFavorite`, `_isDownloaded`, …) behind computed accessors that supply the default. Lightweight migration and CloudKit both accept that shape.
- **Audio files** live in `Application Support/Audiobooks/<book UUID>/`. Covers use SwiftData external storage. Streaming books keep remote URLs on their `AudioTrack`s.
- **Track order** comes from `Audiobook.sortedTracks`.
- **`ReadingSession`** snapshots book metadata so stats survive book deletion.

## Feature references

Each file in `docs/ios/` records what the code can't tell you about one area: its invariants, the reasons behind them, and its traps. Read it before changing that area, and update it in the same commit as any behavior change it describes.

- `playback.md`: `AudioPlayerManager`, chapters, sleep timer, Now Playing and remote commands, titles and rename, equalizer, reading sessions and stats.
- `ai.md`: Apple Intelligence, smart save, moment naming, transcription, recaps, welcome-back cards, `FoundationModels` limits.
- `purchases.md`: StoreKit products, Unpaged Plus, legacy unlocks, the coffee tip, trial and price copy, App Review reachability.
- `icloud-sync.md`: the sync gate, CloudKit, orphans, fingerprints, restore and merge, archived free books, Cloud Library, deleting synced records.
- `free-books.md`: LibriVox browse and design, catalog sync, search, streaming, downloads and Live Activity, samples, collections, other recordings, the legacy CarPlay catalog.
- `audiobookshelf.md`: the Audiobookshelf source, login and tokens, item decoding, browse cache, downloads, progress sync, plain-http hosts.
- `onboarding.md`: the welcome flow, its scenes and permission requests, home-tab choice.
- `system-surfaces.md`: CarPlay, widgets, Siri and App Intents, `unpaged://` links, library moment search.

## Testing

These rules apply to iOS and Android alike:

- Highly prefer E2E tests as the sole testing mechanism. Use them to prove complex features work, and end each run with a verifiable, repeatable artifact.
- Unit tests come before the code they cover, never after.
- Write an isolated test only when a system must be tested alone. First write down every way it could fail, then write the tests from that list, then the implementation.
- Keep an isolated test only when it catches a concrete bug the E2E assertions miss. Name that failure and the E2E gap. Delete a test that repeats constructor defaults, getters, copied constants, mock bookkeeping or behavior E2E already asserts.
- E2E evidence includes the exact rerun command, the source revision and working-tree patch, device and runtime, fixture setup and machine-readable results. Add screenshots, recordings or exported state when the outcome is visual. Keep evidence outside Git and link it from the handoff or PR.

iOS specifics:

- Before a release build, run the native E2E suite (`e2e/`) and the retained Swift tests serially. Suites share process-wide state (the `Audiobooks` folder, `MPNowPlayingInfoCenter`), so the shared scheme marks both test targets non-parallelizable.
- StoreKit tests load the `Products.storekit` copy bundled in the app, because Xcode Cloud test runs can't read the repository copy.
- In-memory test containers pass `cloudKitDatabase: .none` to `ModelConfiguration`. The default picks up the app's CloudKit entitlement and fails validation. The one intentional CloudKit validation is `SchemaCompatibilityTests`, on a file-backed temp store.
- Hold a test container in a local (`let container = try makeContainer(); let context = container.mainContext`). Chaining `.mainContext` off the call deallocates the container and crashes the host app on the first fetch.
- Shared mocks in `PagelessTests/Mocks/` serve retained isolated tests only. A new protocol needs no mock or unit suite.
- DEBUG launch hooks for E2E live in `Pageless/App/E2EFixtures.swift`, and `e2e/README.md` documents them.

## Keeping docs true

- Write invariants and reasons. Point at the code for counts, ids, thresholds, prices, versions and file lists, because copies of them go stale without anyone noticing.
- Implementation plans, design specs, handoff notes and validation logs are temporary. Keep only active work in the repo. Once the work merges, fold any durable decision into this file, `android/AGENTS.md` or the matching `docs/ios/` reference, then delete the artifact. Run evidence goes in the PR.
- `docs/research/` holds dated research that is still actionable. Delete a note once its recommendation ships or is dropped.
- `store-listing/` holds App Store listing drafts for the next version, not the submitted one.
