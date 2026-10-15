# AGENTS.md

Shared instructions for coding agents in this repo. Codex reads this file; Claude Code imports it through `CLAUDE.md`, which adds only Claude-specific tooling notes.

## The app

Unpaged is an audiobook player for iPhone, with a native Android port. Three names are historical layers and each stays where it is:

- **Unpaged**: App Store and home-screen name. All new user-facing copy says "Unpaged".
- **Pageless**: Xcode scheme, source folders (`Pageless/`, `PagelessTests/`, …) and bundle id prefix `andreibaludev.Pageless`.
- **Ebooker**: the GitHub repository.

The marketing version lives in `VERSION` and in `MARKETING_VERSION` in `project.pbxproj`; read it there when it matters.

## Where to start

Read the matching file before changing anything in its area:

- **Android** (`android/`): `android/AGENTS.md`. The iOS sections below cover the Apple app; the iOS code is Android's behavior spec.
- **An iOS feature**: its reference under "Feature references" below.
- **A release**, an App Store Connect upload or an Xcode Cloud build: `docs/ios/release.md`.
- **Marketing site** (`site/`): `site/README.md`.
- **E2E suite** (`e2e/`): `e2e/README.md`; scope and latest results in `e2e/COVERAGE.md`.
- **App Store performance** (downloads, sales, subscriptions, ASO): pull App Store Connect data with the `app-store-connect-analytics` plugin when it is installed. Bundle id and SKU: `andreibaludev.Pageless`.
- **Issues and Wayfinder maps**: `docs/agents/issue-tracker.md`.

## Hard rules

- **The repo is public.** API key ids, issuer ids, `.p8` contents, signing files and tokens live outside it (`~/.appstoreconnect/` and similar). Keep every credential out of commits, logs and PR text.
- **Apple frameworks only.** The iOS app links no third-party package. Build features from system frameworks.
- **Xcode Cloud builds run only when the owner asks.** Pushes start nothing; `docs/ios/release.md` has the script.
- **Public docs follow the app.** `support.md`, `privacy-policy.md` and `EULA.md` are the source for the App Store support, privacy and terms pages (the site renders them at `/support/`, `/privacy/`, `/terms/`), and public GitHub Gists mirror them. Update the source in the same commit, then the matching Gist:
  - permissions (`NS*UsageDescription` in `Info.plist`) → support + privacy
  - network behavior, third-party services, collected data → privacy
  - AI features, purchase terms, trials → all three (EULA §3 holds the purchase terms)
  - minimum iOS, supported devices, new user-visible features → support
  - contact email or developer name → all three, spelled "Andrei Baluta" everywhere

## Build & Run

iOS builds and tests need macOS with Xcode: the owner's Mac, or Xcode Cloud on request. Read tool and runtime versions from the machine (`xcodebuild -version`, `xcrun simctl list runtimes`). On a Linux host, such as a cloud session, nothing iOS builds or runs: verify by reading code, and say in the handoff what you could not run.

**Codex** has XcodeBuildMCP, with project, scheme and simulator defaults pinned in `.xcodebuildmcp/config.yaml`. Call `mcp__XcodeBuildMCP__session_show_defaults` first. Build with `build_sim` / `build_run_sim` (or the `_device` variants), clean with `clean`, and test with `test_sim` plus `extraArgs: ["-parallel-testing-enabled", "NO"]`.

**Claude Code** uses the CLI through `Bash`:

```bash
xcodebuild -project Pageless.xcodeproj -scheme Pageless \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -configuration Debug -derivedDataPath <scratch>/dd build
```

Swap `build` for `test -parallel-testing-enabled NO`. `xcodebuild -showdestinations -project Pageless.xcodeproj -scheme Pageless` lists valid simulator and device ids. Always pass a `-derivedDataPath` inside your scratch directory so runs don't share DerivedData. A clean build takes minutes: run it in the background and tail the log.

Use a physical iPhone only for what a simulator can't show: background audio, CarPlay, StoreKit against a sandbox account, and on-device Apple Intelligence.

### Simulator

Drive the simulator with the tools in your toolset. Codex: XcodeBuildMCP (`screenshot`, `snapshot_ui`, taps). Claude Code: `mcp__Claude_Code_iOS_Simulator__control` (`attach`, `screenshot`, `tap`, `swipe`, `text`). Both: `xcrun simctl`.

```bash
xcrun simctl list devices available          # pick a udid every run
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid> -b            # wait until booted
xcrun simctl install <udid> <path>/Pageless.app
xcrun simctl launch  <udid> andreibaludev.Pageless
xcrun simctl io <udid> screenshot shot.png   # then open the png
```

- Look up the udid each run and pass it to every command and MCP action. With two devices booted, `booted` silently picks one.
- Simulators run headless; no Simulator window is needed.
- The Xcode developer directory is already configured. Diagnose tool errors without changing `xcode-select`.
- Claude Code: call `attach` before building. It opens the owner's panel and fails harmlessly when nothing is booted. Coordinates are device points from the top left.
- The first MCP action on a new device raises an access request the owner must answer. With nobody there to answer, capture with `simctl io` instead.
- Wait at least a second after an action before capturing. Transitions animate, and a frame with two screens blended is a capture taken too early.
- Open and look at an image before citing it as visual proof.
- Useful extras: `simctl ui <udid> appearance dark|light`, `simctl status_bar <udid> override --time 9:41`, `simctl privacy <udid> grant microphone andreibaludev.Pageless`, `simctl uninstall` for a clean-install or onboarding run.
- AI coverage depends on the runtime: below iOS 26 exercises the `Unavailable…` fallbacks, iOS 26+ the real `FoundationModels` path, and iOS 27 adds its own error handling (`FoundationModelGeneration`). The simulator's model also needs Apple Intelligence enabled on the host Mac; without it a run is non-AI regression coverage only.

## Architecture

Lightweight MVVM with protocol-typed services. The source tree shows what exists; these are the conventions it can't show.

- **Targets follow folders.** `Pageless/`, `PagelessTests/`, `PagelessUITests/` and `PagelessDownloadActivity/` are Xcode synchronized folders: a file added there joins its target with no `project.pbxproj` edit, and a non-code file ships in the bundle. Keep docs and scratch files out of them. The widget extension compiles its own folder plus the few app files the pbxproj names explicitly (such as `DownloadActivityAttributes.swift`).
- **Views** own `@Query`, `@AppStorage` and UI state, and create view models with `@State`.
- **View models** are `@MainActor @Observable` classes. Services arrive through the initializer as protocol types with concrete defaults, so a caller passes only the subject (an audiobook, an item). Pass `modelContext` in explicitly.
- **Services** without long-lived state are `struct`s behind protocols or `enum`s of static functions (import, catalog, sync). Services that own long-lived state (playback, downloads, accounts, entitlements, network, the widget snapshot) are singletons (`static let shared`) or environment objects; reuse them before adding another.
- **`AudioPlayerManager`** owns playback state and is injected with `@EnvironmentObject`. Its `equalizer` is a separate environment object, so EQ views bind without the player.
- **Navigation stays in SwiftUI views.** There are no navigation coordinators or DI containers; `CarPlayCoordinator` exists because CarPlay templates aren't SwiftUI.
- **Library state** comes from computed properties on `Audiobook` (`isStreamingOnly`, `isCloudOnlyOrphan`, `isInActiveLibrary`, `isArchived`). Use them instead of combining raw flags, and check `isDownloaded` before touching a book's files.
- **Covers**: every cover view falls back to `GeneratedCoverView` when `coverArtData` is nil or unreadable; system surfaces use `GeneratedCoverView.renderImage(title:side:)`.
- **Settings** are `@AppStorage` string keys written at each use site, with option enums and raw values in `Models/PlaybackSettings.swift`. Search for a key's string before renaming it; every site must match.
- **Appearance** goes through `.appAppearance(_:)`, which sets `overrideUserInterfaceStyle` on the scene's windows so sheets and covers follow. `.preferredColorScheme` can't return to the system scheme until relaunch.
- **Brand accent** is `Color.amber` (`Utilities/Color+Theme.swift`); the asset catalog's AccentColor is black and white.
- **Security-scoped files**: every `startAccessingSecurityScopedResource` has a matching release path (see `LibraryViewModel.releaseSecurityScopedAccess()`).
- **Completion-handler APIs** (Speech) bridge with `withCheckedContinuation` / `withCheckedThrowingContinuation`.

## Platform gates

- **iOS version.** The deployment target is below iOS 26 (`IPHONEOS_DEPLOYMENT_TARGET`); `FoundationModels` and `SpeechAnalyzer` need 26. Reference those symbols only inside `@available(iOS 26, *)` types or `if #available(iOS 26, *)` blocks. Shared AI result and error types live in `Services/Protocols/`, so older-iOS callers, `Unavailable…` fallbacks and mocks compile ungated. `AppleIntelligenceCapability` decides whether AI surfaces render.
- **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`).
- **Permissions.** The onboarding Permissions scene is the one place the app asks up front. CarPlay can't show a permission prompt, so a feature reachable only from CarPlay checks status and explains instead of asking. The lazy speech request in the transcription fallback stays as the safety net.
- **ATS.** `NSAllowsArbitraryLoads` lets plain-http Audiobookshelf servers work on LAN and VPN. iOS ignores it when `NSAllowsLocalNetworking`, `NSAllowsArbitraryLoadsForMedia` or `NSAllowsArbitraryLoadsInWebContent` is present, so it stays the only ATS key (`docs/ios/audiobookshelf.md`).

## Data layer

SwiftData, with one `ModelContainer` built in `AppDelegate` from two configurations. `"synced"` holds the user's library and goes to the CloudKit private database when sync is on. `"local"` holds the LibriVox catalog cache and never syncs. `AppDelegate` lists which models each holds.

- **Synced models stay CloudKit-shaped**: explicit relationship inverses and no `@Attribute(.unique)`. Only local-store models may use `.unique`. `SchemaCompatibilityTests` validates the synced schema against CloudKit.
- **Columns added after launch** are optional private backing fields (`_isFavorite`, `_isDownloaded`, …) behind computed accessors that supply the default. Lightweight migration and CloudKit both accept that shape.
- **Audio files** live in `Application Support/Audiobooks/<book UUID>/`; covers use SwiftData external storage. Streaming books keep remote URLs on their `AudioTrack`s.
- **Track order** comes from `Audiobook.sortedTracks`.
- **`ReadingSession`** snapshots book metadata so stats survive book deletion.

## Feature references

Each file in `docs/ios/` holds the invariants, reasons and traps for one area: what the code can't tell you. Read it before changing that area, and update it in the same commit as any behavior change it describes.

- `playback.md` — `AudioPlayerManager`, chapters, sleep timer, Now Playing and remote commands, titles and rename, equalizer, reading sessions and stats.
- `ai.md` — Apple Intelligence: smart save, moment naming, transcription, recaps, welcome-back cards, `FoundationModels` limits.
- `purchases.md` — StoreKit products, Unpaged Plus, legacy unlocks, the coffee tip, trial and price copy, App Review reachability.
- `icloud-sync.md` — the sync gate, CloudKit, orphans, fingerprints, restore and merge, archived free books, Cloud Library, deleting synced records.
- `free-books.md` — LibriVox browse and design, catalog sync, search, streaming, downloads and Live Activity, samples, collections, other recordings, the legacy CarPlay catalog.
- `audiobookshelf.md` — the Audiobookshelf source: login and tokens, item decoding, browse cache, downloads, progress sync, plain-http hosts.
- `onboarding.md` — the welcome flow, its scenes and permission requests, home-tab choice.
- `system-surfaces.md` — CarPlay, widgets, Siri and App Intents, `unpaged://` links, library moment search.

## Testing

These rules apply to iOS and Android alike:

- Highly prefer E2E tests as the sole testing mechanism. Use them to prove complex features work, and end each run with a verifiable, repeatable artifact.
- Unit tests come before the code they cover, never after.
- Write an isolated test only when a system must be tested alone. First write down every way it could fail, then write the tests from that list, then the implementation.
- Keep an isolated test only when it catches a concrete bug the E2E assertions miss: name that failure and the E2E gap. A test that repeats constructor defaults, getters, copied constants, mock bookkeeping or behavior E2E already asserts gets deleted.
- E2E evidence includes the exact rerun command, the source revision and working-tree patch, device and runtime, fixture setup and machine-readable results, plus screenshots, recordings or exported state when the outcome is visual. Keep evidence outside Git and link it from the handoff or PR.

iOS specifics:

- Before a release build, run the native E2E suite (`e2e/`) and the retained Swift tests, serially: the shared scheme marks both test targets non-parallelizable because suites share process-wide state (the `Audiobooks` folder, `MPNowPlayingInfoCenter`).
- StoreKit tests load the `Products.storekit` copy bundled in the app, because Xcode Cloud test runs can't read the repository copy.
- In-memory test containers pass `cloudKitDatabase: .none` to `ModelConfiguration`; the default picks up the app's CloudKit entitlement and fails validation. The one intentional CloudKit validation is `SchemaCompatibilityTests`, on a file-backed temp store.
- Hold a test container in a local (`let container = try makeContainer(); let context = container.mainContext`). Chaining `.mainContext` off the call deallocates the container and crashes the host app on the first fetch.
- Shared mocks in `PagelessTests/Mocks/` serve retained isolated tests only. A new protocol needs no mock or unit suite.
- DEBUG launch hooks for E2E live in `Pageless/App/E2EFixtures.swift`; `e2e/README.md` documents them.

## Keeping docs true

- Write invariants and reasons. Point at the code for counts, ids, thresholds, prices, versions and file lists, which go stale silently when copied.
- Implementation plans, design specs, handoff notes and validation logs are temporary. Keep only active work in the repo. Once it merges, fold any durable decision into this file, `android/AGENTS.md` or the matching `docs/ios/` reference, then delete the artifact. Run evidence goes in the PR.
- `docs/research/` holds dated research that is still actionable. Delete a note once its recommendation ships or is dropped.
- `store-listing/` holds App Store listing drafts for the next version, not the submitted one.
