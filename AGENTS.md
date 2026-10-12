# AGENTS.md

Canonical instructions for coding agents in this repo (Codex and Claude Code both read this file).
Claude-Code-only notes — tool availability and Codex delegation — live in `CLAUDE.md`, which imports this file.

## App Identity

- **Marketing name (App Store / home screen)**: Unpaged
- **Xcode scheme**: `Pageless` · **source folder**: `Pageless/` · **bundle id prefix**: `andreibaludev.Pageless`
- **Marketing version**: see `VERSION` (currently 1.5.0)

Three names = intentional historical layers — no "fix". New user-facing copy says "Unpaged".

## Android

The native Kotlin/Compose app lives in `android/`. For Android work, read `android/AGENTS.md` first (rules, architecture, known gaps); `android/README.md` has the build/lint/E2E commands and `docs/android/physical-test-checklist.md` the open device qualification. The iOS build and release instructions below apply to the Apple app, not the Android subtree; use `Pageless/` as a behavior reference for Android.

## External-facing docs

`support.md`, `privacy-policy.md`, `EULA.md` in repo root are the source for the App Store Support / Privacy / EULA pages, published at `/support/`, `/privacy/`, and `/terms/` by `site/build.mjs`. Public GitHub Gists mirror them. Update the source in the same commit when a change touches:

- Permissions (`Info.plist` `NS*UsageDescription`) → support + privacy
- Network behavior, third-party services, data collected → privacy-policy
- AI features, IAP terms, trial mechanics → all three (EULA §3 carries subscription/IAP terms)
- Min iOS / supported devices / new user-visible features → support
- Contact email or developer name → all three (spell "Andrei Baluta" identically)

After editing, update the matching public Gist mirror(s).

### Marketing site

`site/` is a zero-dependency static site: `node site/build.mjs` writes `site/dist/`; preview with `node site/tools/serve.mjs`. `.github/workflows/pages.yml` deploys on pushes to `main`. Home and 404 pages have English, German, Spanish, French, Italian, and Brazilian Portuguese versions; locale strings live in `site/src/i18n/`. `store-listing/` holds localized App Store drafts for the next version, not the submitted version.

Implementation plans, design specs, handoff notes and validation logs (e.g. `docs/superpowers/plans/`, `docs/superpowers/specs/`) are temporary. Keep only active work in the repo; once the work merges, fold any durable decision into `AGENTS.md` / `android/AGENTS.md` and delete the artifact. Run evidence belongs in the PR. `docs/research/` holds dated research that is still actionable; delete a note once its recommendation ships or is dropped.

## App Store Connect Analytics

Use [@app-store-connect-analytics](plugin://app-store-connect-analytics@personal) when pulling Unpaged App Store Connect data for marketing, ASO, launch analysis, sales/download summaries, purchases, subscriptions, or other App Store performance questions. Bundle id / SKU: `andreibaludev.Pageless`. Do not substitute RevenueCat for App Store Connect data unless explicitly requested.

## Release & Submission

Releases go out from the CLI, not Xcode's Organizer. **This repo is public — never commit API key ids, issuer ids, `.p8` contents, or any other credential.** Credentials live outside the repo: `~/.appstoreconnect/issuer_id` and `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` (the key id is the filename; more than one key is present, so pick the one registered for this app). App Store Connect app id `6761081641`.

1. Bump `MARKETING_VERSION` in `project.pbxproj` **and** `VERSION` together, and set `CURRENT_PROJECT_VERSION` above every build already uploaded for that marketing version.
2. Green full test run on the simulator (see "Testing").
3. `xcodebuild archive` (Release, `-destination generic/platform=iOS`) → `xcodebuild -exportArchive` with an `ExportOptions.plist` using `method: app-store-connect`, `signingStyle: automatic`, `manageAppVersionAndBuildNumber: false`.
4. `xcrun altool --validate-app` then `--upload-app` against the exported `.ipa` (it lands in `<export-dir>/Pageless.ipa`, not the export dir itself).
5. Wait for `processingState: VALID`, then attach and submit.

The App Store Connect web UI is a slow SPA that often renders blank in a narrow browser pane; the REST API is faster and scriptable for the last mile — `PATCH /v1/appStoreVersions/{id}/relationships/build`, adding the version to the open `reviewSubmission`, and flipping `submitted: true`. An IAP and the app version submitted together each become a `reviewSubmissionItem` on one submission.

Screenshot display types through the API: the 6.9" set (1320×2868) uploads as `APP_IPHONE_67`, because the API rejects `APP_IPHONE_69` as invalid. The 6.5" set is `APP_IPHONE_65`.

**Python here has no `jwt` or `cryptography` module**, so every off-the-shelf ASC snippet fails. Sign the ES256 JWT by piping the `header.payload` through `openssl dgst -sha256 -sign` and converting the DER `SEQUENCE{INTEGER r, INTEGER s}` to raw `r||s` (32 bytes each).

**Xcode Cloud also builds every push to `main` and uploads it**: `ci_scripts/ci_post_clone.sh` takes the marketing version from `VERSION` and the build number from `CI_BUILD_NUMBER`. Once a version is approved, bump `VERSION` and the pbxproj right away, or every `main` push fails upload with ITMS-90186 / ITMS-90062.

Release checklist beyond the build: IAP review screenshot + review notes must match the *shipping* UI (a stale screenshot showing removed copy is a review risk), external docs pushed to their Gists (see above), and release notes saved on the version.

## Build & Run

**Host**: Mac mini (Apple silicon, macOS 27, Xcode 27). Simulators are always available — build, test, and visual checks all run there by default. A connected device is no longer required for routine work.

**Codex** uses XcodeBuildMCP. Call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/destination (`.xcodebuildmcp/config.yaml` pins project `Pageless.xcodeproj`, scheme `Pageless`, simulator `iPhone 18 Pro`).

- **Build & run**: `mcp__XcodeBuildMCP__build_run_sim` / `build_run_device`
- **Build only**: `mcp__XcodeBuildMCP__build_sim` / `build_device`
- **Tests**: `mcp__XcodeBuildMCP__test_sim` / `test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]` (parallel destinations are unreliable here)
- **Clean**: `mcp__XcodeBuildMCP__clean`

**Claude Code has no XcodeBuildMCP** — use the CLI equivalents through `Bash`:

```bash
xcodebuild -project Pageless.xcodeproj -scheme Pageless \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -configuration Debug -derivedDataPath <scratch>/dd build
```

Swap `build` for `test -parallel-testing-enabled NO`, or the destination for
`'platform=iOS,name=balubalu'` (physical iPhone 17e, UDID `00008150-000203220A10C01C`).
Always pass `-derivedDataPath` into the scratch directory so runs don't fight over
the shared DerivedData. Run builds in the background and tail the log — a clean
build is several minutes.

### Simulator

Check your toolset before planning a run. Codex has XcodeBuildMCP (`screenshot`, `snapshot_ui`, taps). Claude Code has `mcp__Claude_Code_iOS_Simulator__control` (`attach`, `screenshot`, `tap`, `swipe`, `text`). `xcrun simctl` works in both. Don't try to load a tool that isn't in your toolset, and don't treat its absence as a blocker.

`Simulator.app` is not installed, so there is no Simulator window. The Claude Code Simulator MCP works without it (tested 2026-10-08 on Xcode 27). `xcode-select -p` is correct, so never suggest `sudo xcode-select -s`.

```bash
xcrun simctl list devices available          # pick a udid every run
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid> -b            # wait until booted
xcrun simctl install <udid> <path>/Pageless.app
xcrun simctl launch  <udid> andreibaludev.Pageless
xcrun simctl io <udid> screenshot shot.png   # then open the png
```

- Look up the UDID each run. Don't copy one from an old log.
- Claude Code: call `attach` first, before building. It opens the panel for the owner and fails harmlessly when nothing is booted. Pass the `udid` on every action. Coordinates are device points from the top left.
- Each new device raises an access request the owner must answer. With nobody there, Simulator MCP calls on that device fail, so capture with `simctl io` instead.
- Take a fresh screenshot after every action. Transitions animate, so wait at least 1 second between an action and a capture. A frame showing two screens blended is a missing wait, not a bug. Capture again.
- With two devices booted, never use `booted` as a selector. `simctl` picks one of them silently.
- Open and look at the image before calling it visual proof.

Useful extras: `simctl ui <udid> appearance dark|light`, `simctl status_bar <udid> override --time 9:41`, `simctl privacy <udid> grant microphone andreibaludev.Pageless`, `simctl uninstall` for a clean-install/onboarding run. Installed runtimes: iOS 18.0, 26.5, 27.0 — use an 18.0 device to exercise the `Unavailable…` AI fallbacks and a 26.5/27.0 device for the real `FoundationModels` path.

**Device-only cases**: background audio behavior, CarPlay, StoreKit against a real sandbox account, and anything needing on-device Apple Intelligence hardware. `FoundationModels` on a simulator depends on the host Mac having Apple Intelligence enabled; if it can't run, treat that pass as non-AI regression coverage only.

**External packages: none.** Native Apple frameworks only (AVFoundation, MediaToolbox, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, AppIntents, CarPlay, ActivityKit/WidgetKit, Network). RevenueCat was removed — see "In-App Purchases".

## Info.plist / Target Settings (App Store relevant)

- `ITSAppUsesNonExemptEncryption: false`; `UIBackgroundModes: audio`; `NSSupportsLiveActivities: true` (download Live Activity)
- App and widget extension share `group.andreibaludev.Pageless` via `com.apple.security.application-groups`.
- URL scheme `unpaged` — `unpaged://library/downloads` routes to the pinned downloads (`UnpagedRoute`)
- Mic + speech usage descriptions (CarPlay voice search; transcription + AI moment naming)
- Two scene roles: `UIWindowScene` (default) + `CPTemplateApplicationScene` → `CarPlaySceneDelegate`
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `TARGETED_DEVICE_FAMILY = 1` (iPhone-only). AI features gated `@available(iOS 26, *)` + runtime-checked, so the binary installs and runs on iOS 18+ with AI surfaces auto-hidden below iOS 26.

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers (one exception: `CarPlayCoordinator`).

```
Pageless/
├── App/             PagelessApp (@main; scene wiring, Siri handoff),
│                    AppDelegate (ModelContainer; re-runs orphan detection on CloudKit import batches),
│                    CarPlaySceneDelegate, UnpagedRoute (`unpaged://` links),
│                    E2EFixtures (`#if DEBUG` launch hooks for `e2e/`)
├── AppIntents/      AudiobookIntents — `PlayLatestBookIntent` + `UnpagedAppShortcuts`
├── Configuration/   PlusProductID, AIProductID (legacy AI + iCloud ids), CoffeeTipProductID, Products.storekit
│                    (local StoreKit test config, wired into the scheme)
├── Downloads/       LibriVox background URLSession coordinator, on-disk job manifests,
│                    download Live Activity controller (see Free Books → Download)
├── Models/          SwiftData models + settings/stats enums (see Data Layer)
├── ViewModels/      see table; ABS view models live together in ABSViewModels.swift
├── Views/           ContentView (root tabs + per-tab sort + header Plus button), player /
│                    detail / settings / cloud / moment views; subfolders FreeBooks/,
│                    ReadingStats/, Onboarding/, Shelves/Audiobookshelf/
├── Services/        playback, import/AI, stats, EQ, LibriVox, CarPlay, IAP, iCloud sync
│   └── Protocols/   TranscriptionProviding, SegmentTranscribing, MomentAnalyzing,
│                    AudioExtracting, RecapProviding, FreeBookDownloading, ABSCredentialStoring
│                    (iOS<26 `Unavailable…` fallbacks live here too)
└── Utilities/       TimeFormatter, BookDescriptionFormatting, Color+Theme (`amber` accent),
                     AppMotion, LegalURLs
PagelessDownloadActivity/   widget extension rendering the download Live Activity
e2e/                 native simulator E2E suite (see Testing)
screenshots/         App Store screenshot generator (Bun/Next.js; see its README)
```

`PagelessTests/` — retained isolated regressions with shared mocks and media fixtures; SchemaCompatibilityTests validates CloudKit constraints. `PagelessUITests/` — launch + UI tests.

## Data Layer (SwiftData)

**Five models**, split `ModelContainer` built in `AppDelegate`: `"synced"` configuration (`Audiobook`, `AudioTrack`, `Moment`, `ReadingSession` → CloudKit private DB when enabled) and `"local"` (`LibriVoxBook` — never synced).

- Audio files for downloaded books: `Application Support/Audiobooks/[UUID]/`. Covers: SwiftData external storage. Streaming-only books keep remote URLs on `AudioTrack`, `Audiobook.isDownloaded == false`.
- `Audiobook` cascade-deletes its `tracks[]` + `moments[]`. `AudioTrack.contentFingerprint` (SHA-256 hex) drives iCloud orphan matching. `Moment` stores AI fields (categories/quoteLine/characters/mood) JSON-serialized. `ReadingSession` snapshots book metadata (bookID/title/author/isFreeBook) so stats survive book deletion.
- **Schema evolution**: post-launch columns use private backing fields with computed accessors (e.g. `_isFavorite`, `_isDownloaded`, `_contentFingerprint`) for lightweight migration — nullable on disk, safe default in the accessor.
- **CloudKit constraints**: synced models need explicit relationship inverses and must not use `@Attribute(.unique)`. `LibriVoxBook` (local store only) keeps `.unique` on `id`. Never add `.unique` to a synced model.

## Central State: `AudioPlayerManager`

ObservableObject; single source of truth for all playback state, injected via `@EnvironmentObject`. Exposes its `equalizer: AudioEqualizerService` as a separate `@EnvironmentObject` so views bind EQ controls without going through the player.

- AVPlayer orchestration, track queuing, background audio; handles streaming (remote URLs) + local file items uniformly
- Builds per-item `AVAudioMix` via `AudioEqualizerService.makeAudioMix(for:)` so the EQ tap runs in the audio pipeline
- Delegates persistence to `PlaybackPersistence` (progress saves, high-water mark, seek penalty) and remote commands to `NowPlayingUpdater` (Control Center, headphones, CarPlay)
- 1-second periodic time observer feeds `ReadingSessionRecorder.tick(...)`; flushes the recorder on pause, track change, audiobook change, app background, and book finish so partial chunks aren't lost
- **Chapters** — `PlaybackChapter` is computed, never synced: embedded M4B/M4A/MP3 markers (`EmbeddedChapterReader`, including the `und` locale), ABS book-wide markers mapped to track offsets, or one chapter per track. `ChapterListSheet`, player previous/next, and CarPlay use the same list. Navigation steps from pending targets; pause invalidates queued jumps, and timer readings cannot overwrite a pending seek. Track ordering uses `Audiobook.sortedTracks` consistently.
- **Chapter sleep timer** — `SleepTimerOption.endOfChapter` uses raw value `-1`, preserving minute values. `AudioPlayerManager` sets `AVPlayerItem.forwardPlaybackEndTime` from the shared chapter list and handles the end notification before track advance. Seeks, chapter metadata refreshes and track commits retarget it; manual pause keeps it armed, expiry/cancellation/book finish clear it. ABS chapters spanning files use book-global end times. The DEBUG seconds override applies only to minute timers.

## ViewModels

All `@MainActor @Observable`; views create them with `@State`. Initializer injection with protocol-typed services, concrete defaults provided so `ViewModel()` works without arguments.

| ViewModel | Key State | Services |
|-----------|-----------|----------|
| `PlayerViewModel` | pending moment fields (time/name/categories/characters/mood/quoteLine), smart-save warning | `TranscriptionProviding`, `MomentAnalyzing`, `AudioExtracting` |
| `AudiobookDetailViewModel` | moment filters, `isLoadingRecap`, `recapText`, `recapProgressHeadline` | `TranscriptionProviding`, `AudioExtracting`, `RecapProviding` |
| `LibraryViewModel` | `pendingImport`, `urlsHoldingSecurityAccess`, delete/rename candidates | `FreeBookDownloading` (legacy seed catalog) |
| `BrowseLibriVoxViewModel` | search, `syncState`, `featuredBooks`, language/genre/duration filters | `LibriVoxAPIClient`, `LibriVoxCatalogSync` (via SwiftData) |
| `LibriVoxBookDetailViewModel` | persisted identity, `addToLibraryState`, shared-manager request routing | `FreeBookIdentityService`, `StreamingLibraryService` |
| `LibriVoxCollectionViewModel` | collection `state`, locally ordered `books` | `LibriVoxAPIClient`, `LibriVoxCatalogSync` (via SwiftData) |
| `ABSConnectViewModel` / `ABSBrowseViewModel` / `ABSBookDetailViewModel` | connect form + insecure-host warning, library/sections/search, item detail + add/play | `AudiobookshelfClient`, `ABSAccount`, `AudiobookshelfLibraryService` |

## Services

Protocol implementations typically `struct`. `LibraryImportService` and catalog/sync services (`LibriVoxAPIClient`, `LibriVoxCatalogSync`, `FreeBookCatalogService`) = `enum` with static methods. `SamplePlayer` + `NetworkMonitor` = singletons.

| Protocol | Implementation | Framework |
|----------|---------------|-----------|
| `TranscriptionProviding` | `TranscriptionService` | Speech |
| `MomentAnalyzing` | `MomentNamingService` (iOS 26+) · `UnavailableMomentAnalyzer` (iOS 18 fallback) | FoundationModels |
| `RecapProviding` | `RecapService` (iOS 26+) · `UnavailableRecapProvider` (iOS 18 fallback) | FoundationModels |
| `AudioExtracting` | `AudioExtractionService` | AVFoundation (AVAssetExportSession) |
| `FreeBookDownloading` | `FreeBookDownloadService` | URLSession (background) — legacy seed catalog |
| Coffee tip purchase | `CoffeeTipStore` | StoreKit 2 (consumable) |

## AI & On-Device Intelligence

- Welcome-back recaps appear above book-detail playback controls after three days away and three minutes of saved progress, with the local AI + Plus gates and a default-on `AISettingsKey.welcomeBackRecaps` toggle. Dismissal is device-local and keyed to the last listening date; passive failures stay hidden. Cached anchors may lag the saved position by up to 60 seconds, never lead it.

- `MomentNamingService` — moment analysis: name, note, categories, quoteLine, characters, mood. `RecapService` — `RecapGenerationResult` (recap text + optional `progressHeadline`). Both `@available(iOS 26, *)`.
- **Transcription is two-tier.** Primary: `SpeechAnalyzerTranscriptionService` (`SegmentTranscribing`, iOS 26 `SpeechAnalyzer`/`SpeechTranscriber`) reads the audio file's frame range directly — no export, no temp file, no length cap, punctuated output, **no speech-recognition permission**. Any throw falls back silently to the legacy path: `AudioExtractionService` export + `TranscriptionService` (SFSpeechRecognizer, `addsPunctuation`, on-device when supported, en-US locale fallback) — the only path that requests speech authorization. Don't add an up-front auth gate to smart save/recap; auth belongs to the fallback alone.
- **Generation hardening (both services).** `SystemLanguageModel(guardrails: .permissiveContentTransformations)` — default guardrails false-positive on fiction (violence/romance); these are built for transforming the user's own content. Greedy sampling + `maximumResponseTokens` for deterministic, latency-bounded extraction. Mood/categories use `@Guide(.anyOf…)` constrained decoding; guide literals are duplicated (macro args), so keep the actual `@Guide` values aligned with `MomentEnums` when changing categories or moods. `FoundationModelGeneration.run` maps `LanguageModelSession.GenerationError` → `unsafeContent`/`failed` and retries once (context-window overflow → retry with transcript tail; rate-limit/concurrent → delayed retry). Catch `MomentNamingError.unsafeContent`/`RecapError.unsafeContent` — never string-match error descriptions.
- **Verified-verbatim quotes.** `MomentNamingService.verifiedQuote` keeps the model's quote only if the transcript contains it (case/diacritics/punctuation-folded), snaps near-misses to the best-matching transcript sentence (≥70% word overlap), drops fabrications.
- **Prewarm.** `MomentAnalyzing.prewarm()` (default no-op) loads the model ahead of the first analysis; `PlayerView` calls `viewModel.prewarmSmartSave()` on appear/when smart save flips on. The prewarmed session (`PrewarmedMomentSession`) is consumed by exactly one analysis — sessions are multi-turn, never reuse across analyses.
- `AppleIntelligenceCapability` — runtime detection gating AI UI visibility; iOS-18-safe (internal `if #available(iOS 26, *)` branches). `isSmartNamingAvailable` gates on model availability only (SFSpeechRecognizer is no longer a hard requirement). AI is isolated behind protocols; the app works fully without Apple Intelligence.
- `PlusEntitlementStore.shared` — StoreKit 2 owns consolidated AI + iCloud access through `Transaction.currentEntitlements`; legacy AI unlock and iCloud subscriptions remain recognized.
- **iOS 18 deployment-target rule.** `FoundationModels` is iOS 26-only. Shared types (`MomentAnalysis`, `MomentNamingError`, `RecapError`, `RecapGenerationResult`, `SegmentTranscriptionError`) live in the protocol files so iOS-18 callers + mocks need no availability gating. ViewModel default inits branch on `if #available(iOS 26, *)` to pick real service vs `Unavailable…` stub. Never reference `FoundationModels` symbols outside an `@available`-gated type or `if #available` block.
- **~4096-token budget shared between input + output** (same model regardless of guardrails). In `@Generable` structs, order cheap structured fields first, longest prose field last — fields generate in declaration order and the trailing one gets clipped when the budget runs out (recap's `progressHeadline` comes **before** `recap` for the same reason). Post-process free-text fields for mid-sentence truncation (see `MomentNamingService.trimToCompleteSentences` / `sanitizedQuoteLine`); never trust the model to honor word/sentence-count guides.

### In-App Purchases

All purchases are StoreKit-owned. `PlusEntitlementStore.shared` owns AI and iCloud access; the coffee tip is a repeatable consumable with no entitlement or restore path. No third-party purchase SDK is used.

| Product | Store ID | Type | Owner store |
|---------|----------|------|-------------|
| Unpaged Plus monthly | `andreibaludev.Pageless.plus.monthly` | Auto-renewable monthly | `PlusEntitlementStore.shared` |
| Unpaged Plus yearly | `andreibaludev.Pageless.plus.yearly` | Auto-renewable yearly | `PlusEntitlementStore.shared` |
| Legacy AI Features unlock | `andreibaludev.Pageless.ai_unlock` | Non-consumable, recognized for existing customers | `PlusEntitlementStore.shared` |
| Legacy iCloud Sync | `andreibaludev.Pageless.icloudsync.monthly` | Auto-renewable monthly, recognized for existing customers | `PlusEntitlementStore.shared` |
| Buy me a coffee | `andreibaludev.Pageless.tip.coffee` | Consumable, one-time optional support | `CoffeeTipStore` |

- **Launch cache.** `AppDelegate.init` reads `PlusEntitlementStore.isSubscribedAtLaunch()` before SwiftUI environment objects exist to choose the SwiftData CloudKit database. Live entitlements come from StoreKit.
- **Trial copy.** Derive the trial period and price from the loaded StoreKit product. `freeTrialDisplay` returns nil unless its introductory offer uses `.freeTrial`. The local `Products.storekit` configuration carries a one-week trial on both Plus plans (`paymentMode: "free"` in the JSON schema); App Store Connect remains the production source of offers and pricing.
- **Reachability (Apple 3.1.1).** The iCloud Sync purchase must stay reachable in the reviewed build: library-header Plus button (`sparkles`, `plusButton`, shown **unconditionally**) → `PlusHubView` (`UnpagedPlusCard`) → "Subscribe" — **not** hidden behind iCloud sign-in. Settings → "Unpaged Plus" pushes the same hub as a secondary path; Settings leads with real settings, not the offer. A prior build was rejected under 3.1.1 for this.
- **RevenueCat (removed).** StoreKit 2 is the only entitlement owner. No RevenueCat package, imports, configuration, observer calls, credentials, or reactivation blocks remain in source. Any future provider reintroduction needs a new product/privacy plan and matching external-document updates; credential rotation remains maintainer-owned and never belongs in this repository. End-to-end third-party verification, if separately approved, needs TestFlight rather than local `Products.storekit` receipts.
- **Buy me a coffee.** `CoffeeTipStore` loads the single localized consumable product, serializes purchase calls on the main actor, finishes only verified coffee transactions (including delayed approvals and unfinished startup transactions), and exposes explicit cancelled/pending/unavailable/failed/succeeded states. A verified tip never unlocks a feature or creates an entitlement, and no restore button is provided because consumables cannot be restored. Local `Products.storekit` uses $2.99 as a tentative test price; App Store Connect remains the production source of price and localization.

## Feature Systems

### Library moment search

The header magnifying glass opens `MomentSearchView` across all books, including archived and cloud-only records. In-memory matching folds case and diacritics, requires every query word, and ranks name/book hits above notes/quotes, then recency. Empty search shows the latest 30 moments grouped by book. Search uses `MomentRow` and `playTrack(at:in:time:)`; unavailable audio and offline streaming rows show a disabled reason. No new stored fields or network requests.

### Free Books — two parallel systems (by design)

1. **LibriVox catalog (primary, iPhone)** — 20,000+ books, cached in `LibriVoxBook` via `LibriVoxCatalogSync` (24h incremental sync). UI: "Shelves" tab (internal `LibraryTab.freeBooks`, LibriVox source) → `BrowseLibriVoxView` → `LibriVoxBookDetailView`.
   - **Browse design ("Open Shelf" editorial).** `BrowseLibriVoxView` types through a private 4-size `FBType` scale (eyebrow 10 / body 12 / title 15 / headline 19) — serif (`design: .serif`) titles/authors/blurbs, small-caps `FBEyebrow` metadata, numbered chart rows. Section headers ("Collections", "Popular Classics", …) keep the app's classic voice: `.subheadline.weight(.semibold)` + `.primary` + hairline rule — don't re-grow them or swap them to eyebrows. Filter labels (`LANGUAGE/GENRE/LENGTH`) always `.primary`; selection = 2pt amber underline, not color. **Daily hero**: `todaysPick` resolved by `loadTodaysPick` (deterministic `curatedClassicIDs[dayOfYear % count]`, local cache only); `chartBooks` excludes it so hero and chart never duplicate.
   - **Add to Library (streaming)** — `StreamingLibraryService` creates an `Audiobook` with `isDownloaded == false` + remote URLs per `AudioTrack`. No files written; needs network at playback.
   - **Download** — session-wide `LibriVoxDownloadManager` (built by `LibriVoxDownloadRuntime`) owns shared progress, cancellation, retry, failure, and completion state. Transfers run on a background `URLSession` through `LibriVoxBackgroundDownloadCoordinator`, with per-job manifests on disk (`LibriVoxDownloadManifestStore`) so work survives suspension and relaunch; `AppDelegate` routes background-session events. `DownloadLiveActivityController` mirrors progress into a Live Activity rendered by the `PagelessDownloadActivity` extension. `LibriVoxDownloadService` fetches all tracks; tags `isFreeBook = true`, `catalogId = book.id`, keeps each track's `remoteURLString`, and promotes streaming/archived entries in place. Shelves and Library show the same pinned download state; detail routes observe/request work without owning it.
   - **Sample** — `SamplePlayer`, 20s preview starting 30s into the first track; inline icon = shared `LibriVoxSampleButton` (in `LibriVoxBookRow.swift`). `LibriVoxBookDetailView.fetchSampleURL` resolves the track URL itself (browseViewModel → `book.cachedTracks` → audiotracks feed) because pushes from the alternatives section carry no `browseViewModel` — don't make sample playback depend on the VM being present. **Network gating** — check `NetworkMonitor.shared.isConnected` before sample play, sync, streaming.
   - **Covers intentionally not fetched** (LibriVox cover URLs unreliable): both services set `coverArtData = nil`; `GeneratedCoverView` renders the letter template. Don't reintroduce remote cover fetches here.
   - **Classics-first load order.** `BrowseLibriVoxViewModel.triggerSyncIfNeeded` awaits `performPreload` (curated `curatedClassicIDs` via `LibriVoxAPIClient.fetchBooks(ids:)` → `LibriVoxCatalogSync.seed`) **before** kicking off the full `performSync`. Search and filters stay interactive throughout, with a non-blocking preparation banner (`isLoadingFullCatalog`).
   - **Catalog concurrency/lifecycle.** `LibriVoxCatalogStore.make` constructs its `@ModelActor` off the main actor; page writes, searches, and filter aggregation use its background context. Commit each 50-book page before persisting the next offset in `LibriVoxSyncCheckpoint`. Backgrounding raises a pause flag and uses a short background task to save the current page; foregrounding resumes the cursor with one in-flight sync. Keep genre backfill completion separate from partial counts.
   - **Search during preparation.** Text/genre requests use the live feed and merge matching cached rows. The feed has no language or duration query parameter: those filters narrow results locally, with a partial-results notice for an incomplete cache. Saved-page updates refresh cached results and filter menus at most every two seconds; sync completion reruns the active query locally. `extended=1` is required for genres, and query values must escape `&`, `=`, and `+`.
   - **Hardened API client — never surface raw `DecodingError`.** The feed returns `{"error":"…"}` with HTTP 200 (no match) or HTML (server hiccup); `fetchData` validates status (→ `LibriVoxAPIError.serverUnavailable`), the lenient `decode` helper maps error-envelope/empty to `[]` and unparseable to `.unreadableResponse`. `URLError` deliberately **not** wrapped so `isNetworkUnavailable` offline classification still works. `LibriVoxCatalogSync.fetchPageWithRetry` retries transient page failures (3 attempts, linear backoff).
   - **Offline/empty states** (`BrowseLibriVoxView`): `isOfflineWithNoData` / `isOfflineWithCachedData` / `loadFailedWithNoData`, all featured-aware (cached classics count as "has data").
   - **Collections** — `LibriVoxCollection.all`: hand-curated static shelves (struct + bundled LibriVox project IDs, no backend), horizontal card rail atop the browse chart (`collectionsRail` in `browseContent`) → `LibriVoxCollectionView`. `LibriVoxCollectionViewModel.load` resolves local-first from the `LibriVoxBook` cache, fetches only missing IDs via `LibriVoxAPIClient.fetchBooks(ids:)` and seeds through `LibriVoxCatalogSync.seed` (so the full sync dedupes by `id`); curated ID order preserved; offline-with-partial-cache degrades to cached subset. IDs must be verified against the live feed API before adding.
   - **Other Recordings** — `LibriVoxAlternativesFinder`: groups re-recordings of the same text from the local cache (zero network). Normalized title key strips only *known* LibriVox suffixes — `(version N)`, `(dramatic reading)`, `(version N dramatic reading)`, `(abridged)`, `(unabridged)`, `(solo)`, `(group)`, stacked OK — then folds case/diacritics; unknown parentheticals (translations) never merge. Match = same `language` + same `authorDisplay` (#Predicate) + equal key, excluding self; sort original → versions ascending → other readings. `LibriVoxAlternativesSection` (rows: version badge / duration / inline 20s sample / push to detail) shared by `LibriVoxBookDetailView` (bottom) and `AudiobookDetailView` (free books, resolved via `catalogId`). **Empty state must render a zero-height anchor, not nothing** — a structurally absent view never fires the `.task` that loads alternatives.

2. **Legacy seed catalog (CarPlay)** — `FreeBookCatalogService`: 5 hand-picked Internet Archive classics, downloaded via `FreeBookDownloadService` (background URLSession; published progress/errors). Consumed only by `CarPlayCoordinator` + `LibraryViewModel`. **Don't extend this path for new iPhone features — use the LibriVox path.**

### Audiobookshelf (user's own server, Shelves source)

- `BookSourceRegistry.sources` = LibriVox + Audiobookshelf (always listed; choosing it unconfigured opens `ABSConnectView`). `isConfigured` follows `ABSAccount.shared` (Keychain via `ABSKeychainCredentialStore`). `ShelvesSourcePreference` falls back to LibriVox when ABS is not connected.
- `AudiobookshelfClient` (actor) — login (`x-return-tokens`) or API key (Bearer); 401 → one shared refresh. An API-key-shaped JWT that gets 401 maps to `.inactiveAPIKey`.
- **Tokens never persist outside the Keychain.** `AudioTrack.remoteURLString` for ABS books is token-less (`storedStreamURL`); `AudioPlayerManager` appends `?token=` at play time via `playbackURL(forStoredURL:)` (refreshes a session with <45 min left). `AudiobookshelfLibraryService.addToLibrary` refuses credential-bearing URLs.
- ABS books keep `Audiobook.absItemID` when downloaded and always have `isFreeBook == false`. `ABSDownloadManager` uses a sibling background URLSession and durable token-less manifests, stages all tracks, then promotes the existing row in place. Files use `Application Support/Audiobooks/[UUID]/`; local playback and AI use the same paths as imported books. Remove Download preserves progress, moments and EQ and returns to streaming. `OrphanDetectionService` checks every track file of a downloaded ABS book; any missing file (e.g. the row synced from another device) returns it to streaming, never `isCloudOnlyOrphan`. ABS downloads show in the Library's pinned downloads but have no Live Activity. Cloud Library puts downloaded ABS books in On this iPhone and others in Streaming. Delete offers Remove Download or Remove from Library; neither deletes server content.
- ABS browse GET responses are cached under Caches, scoped by server and username, with credential fields and URL tokens removed. Only unreachable/offline/5xx failures fall back to saved responses; Each screen load binds its own `ABSCacheUse` task local, which records whether any of its requests (including `async let` children) came from the cache; overlapping loads never share or reset it. Cached shelves show an offline banner; server actions are disabled while downloaded audio remains playable. Settings shows downloaded audio size, removes all downloads, and offers keeping or removing audio on disconnect. Cancelling removes partial transfers without promoting the book. Background session events drain through AppDelegate after file and manifest writes.
- Rich browse follows the [ABS API](https://api.audiobookshelf.org/) with paginated `/api/libraries/{id}/series` and `/collections` (`books` arrays). Series sequence comes from each book's top-level `sequence`; numeric sequences sort numerically (including fractions), unnumbered books last by title. Collections preserve server book order. Expanded metadata supplies individual author IDs and narrator names; person pages use paginated library items with `filter=authors.<base64(id)>` or `narrators.<base64(name)>`, scoped to the current library. Progress filters combine with search using cached per-user media progress. Every new GET uses `ABSResponseCache`, including filtered person queries. Series/collection screens push `ABSGroupRoute` values whose destination is registered on `ContentView`'s `NavigationStack`: a destination inside the paged tab content is never registered, and a view-destination link there pops its screen when the pager reloads it.
- Progress: `ABSProgressReporter` persists the latest token-free book-global position per item in a local UserDefaults outbox, retrying on connectivity, foreground, connect/refresh and reports. Before sending a queued entry it reads the server position and drops the entry when the server's `lastUpdate` is newer; a failed read keeps it queued. Disconnect and server or user changes clear it; permanent 4xx failures drop it. Resume and re-add adopt server positions only when `lastUpdate` is newer than `Audiobook.absProgressWrittenAt` (`lastPlayedAt` for rows saved before it existed) and any pending report, with a difference over 30 seconds. Resume requests use a two-second timeout. Local writes use the nullable `_absProgressWrittenAt` backing field; intentional rewinds take precedence by timestamp. Finish reports include `isFinished`.
- ATS: `NSAllowsArbitraryLoads` (+ `NSLocalNetworkUsageDescription`) so plain-http self-hosted servers work over LAN and VPNs (Tailscale MagicDNS `*.ts.net`, 100.64/10). Do **not** add `NSAllowsLocalNetworking`/`…ForMedia`/`…InWebContent` alongside it — iOS then ignores `NSAllowsArbitraryLoads`. `AudiobookshelfClient.isPrivateNetworkHost` classifies LAN/loopback/link-local/CGNAT/ULA/`.local`/unqualified/`*.ts.net` hosts; plain http to any other host triggers a one-time "isn't using HTTPS" confirmation in `ABSConnectView` before credentials are sent (`needsInsecureConnectionWarning`, skipped for the already-connected server). Unreachable servers (e.g. Tailscale off) map to `.unreachableServer` with a VPN/Tailscale hint.
- UI in `Views/Shelves/Audiobookshelf/` (connect sheet, browse, detail, `ABSServerSettingsView`); view models in `ViewModels/ABSViewModels.swift`.

### Reading Activity & Stats

- `ReadingSession` = only persisted row — one chunk = one book × one wall-clock hour bucket, metadata snapshotted.
- `ReadingSessionRecorder` (`@MainActor`) owned by `AudioPlayerManager`, ticked from its 1s observer while playing. Chunks emit every ~5 min of continuous play; pause / track change / book change / background / finish flush; chunks < 30s dropped as scrub noise.
- `ReadingStats.compute(sessions:booksFinished:)` = pure aggregate → totals, best day/hour/dow, streaks, top author, longest book, free-book share, per-day map. No persistence; recomputed when the sessions `@Query` changes.
- Favorites tab pins `ReadingActivityCard` above the grid (only when `stats.hasAnyActivity`); tap pushes `ReadingStatsView` with a zoom transition out of the card's heatmap. Full view = `ReadingStatsSections` in a `LazyVStack` with `revealOnAppear` + `CountUpText` choreography. `ReadingHeatmap` + `HeatmapPalette` (`.amber`) shared by card + full view.
- `ReadingActivitySeeder` is `#if DEBUG`-only (seeds 113 days of synthetic activity). Never call it from release code paths.

### Equalizer (per-book)

- `EqualizerSettings` — 5 bands (60Hz/230Hz/910Hz/3.6kHz/14kHz), presets (flat, voiceBoost, bassBoost, trebleBoost, podcast, custom), preamp 0–12 dB, band gain ±12 dB
- `EqualizerTap` — C-level `MTAudioProcessingTap`: biquad filters + soft limiter on the realtime audio thread; coefficients updated under `os_unfair_lock`
- `AudioEqualizerService` (ObservableObject) — live `@Published` state, persists to `Audiobook.equalizerConfiguration`, builds the `AVAudioMix` injected into each `AVPlayerItem`
- `EqualizerSheet` — UI; reads/writes via `@EnvironmentObject AudioEqualizerService`

### Onboarding

Standalone welcome flow, shown once on first launch (and via Settings → "Reset Onboarding"). Replaced the old spotlight walkthrough — no `OnboardingStep` / `SpotlightOverlayView` / `.spotlightTarget()` machinery; don't reintroduce.

- **`OnboardingManager`** — completion gate only: `isComplete` (persisted as `onboardingComplete`), `complete()`, `reset()`. Init migrates legacy users (old `onboardingPhase == 3` counts as complete). `ContentView` presents `OnboardingFlowView` via `.fullScreenCover` while `!isComplete`.
- **`OnboardingFlowView`** — paged vertical `ScrollView` (`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`), seven full-screen scenes (Choice → Permissions → Playback → Stats → Apple Intelligence → iCloud → Done), right-edge progress-dot rail. The active scene index drives reveal/count-up/stagger animations — `.onAppear` is wrong here (paged rows instantiate before they center).
- **Preference controls bind live to existing `@AppStorage` keys** (`resumeBacktrackSeconds`, `skipBackSeconds`, `skipForwardSeconds`, `momentBacktrackSeconds`) — persistence automatic, final-scene summary shares one source of truth. "Open Library" calls `complete()` and routes to the chosen home tab. **"Shelves" choice persists** via `@AppStorage("startOnFreeBooks")`: when true the app lands on Shelves on **every** launch (one-time `.onAppear` guard in `ContentView` applies it for relaunched users) and tab order becomes Favorites / Shelves / Library (`LibraryTab.order`; it drives both `tabPicker` and the swipeable `libraryContent`). "My books" + all legacy users: false — order Favorites / Library / Shelves. Internal `.allBooks`/`.freeBooks` symbols and stored keys remain unchanged.
- **Scene 2 (Permissions) is the app's only proactive permission request point** — `OBPermissionsScene`: two cards (Microphone via `AVAudioApplication.requestRecordPermission`, Speech Recognition via `SFSpeechRecognizer.requestAuthorization`); buttons animate to "Allowed" only when the system grants. `.denied`/`.restricted` taps open the app's Settings page — no extra error UI. Cards seed from live authorization status (re-seeded on `scenePhase == .active` to catch Settings grants). Skippable — never block scrolling; both-granted auto-advances after ~0.8s only if still on the scene. The Done summary's "Voice access" row (Allowed / Mic only / Speech only / Skipped) reads the same root state. Launch-time priming was removed; the lazy speech-auth request in `TranscriptionService` stays as the safety net.
- **Scenes 5 (Apple Intelligence) and 6 (iCloud Sync) are informational only** — no paywall, no toggles; don't wire purchase/sync state into them.
- **`OnboardingScenes`** = seven scenes + widgets (choice cards, permission cards, `OBResumeSlider`, chip rows, stepper, `OBHeatmap`, moment-naming card, `OBSyncGraphic`, summary). **`OnboardingTheme`** = tokens (`OB.*` colors, `OBMotion`), type primitives (`OBEyebrow`/`OBHeadline`/`OBSub`/`obSerif`), `obReveal`/`obParallax` modifiers.
- **Must render identically on every device/iOS version**: fixed point sizes, fixed 402pt centered content column, `.dynamicTypeSize(.large)` clamp at root (never Dynamic Type), app's own Appearance choice applied at the window (see Settings & Preferences). All animations honor Reduce Motion.

### iCloud Sync (paid feature)

Library metadata, progress, moments, EQ config, reading sessions sync via CloudKit private DB (container `iCloud.andreibaludev.Pageless`). Audio files are **not** synced — re-acquired per device. Gated by Unpaged Plus or an active legacy iCloud Sync subscription (see In-App Purchases).

- **`IcloudSyncGate`** — single decision point: active subscription (`PlusEntitlementStore.isSubscribedAtLaunch()`) AND `iCloudSyncEnabled` UserDefaults toggle AND `FileManager.ubiquityIdentityToken`. If any is false, `AppDelegate` builds the container with `.none` database.
- **Orphan detection** — `OrphanDetectionService` runs at launch and after every `NSPersistentCloudKitContainer.eventChangedNotification` import. A book marked `isDownloaded = true` whose storage folder is absent gets flipped to `isDownloaded = false` (recoverable orphan).
- **Fingerprinting** — `LibraryImportService.fingerprint` hashes SHA-256 over the first + last 1 MB (whole file if ≤ 2 MB) + little-endian file size + duration in ms, per imported track → `AudioTrack.contentFingerprint`. Android's backup restore uses the same algorithm; keep them in step. `FingerprintBackfillService` backfills existing tracks on first launch after upgrade.
- **Restore on re-import (own books)** — importing on a new device, `LibraryViewModel` calls `OrphanRestoreService.findMatch` (fingerprint vs orphan candidates). Match → `RestoreMatchSheet` ("Restore from iCloud" / "Add as new"). `adopt` rewrites the orphan's `AudioTrack` records in place, preserving moments/progress/EQ.
- **Match by id (free books)** — free books match on `catalogId`, not fingerprint. `FreeBookIdentityService` resolves downloaded, streaming, or archived matches deterministically. Add/download/legacy CarPlay paths reuse that row; archived rows reactivate in place, preserving progress, moments, favorites, and EQ. No "Add as New" path exists for a matched free book. Removing a free book with sync on calls `LibraryImportService.archiveFreeBook` (drops files, sets `isArchived = true`, keeps the synced record + remote URLs). `isArchived` = free-book analogue of an own book's `!isDownloaded` orphan state — needed because free `!isDownloaded` alone is ambiguous (active streaming vs removed).
- **`CloudLibraryView`** — the full iCloud Library (every book ever added, so the backup is visibly verifiable), not just orphans. Reachable via the library-header Plus button → `PlusHubView` → "iCloud Library" (row shown only when `IcloudSyncGate.isEnabled()`), and via Settings → iCloud Sync → iCloud Library. (The header button was the iCloud button, which had replaced the old header sort button — sort moved to per-tab chevron menus.) Four mutually exclusive buckets: **On this iPhone** (`isDownloaded && !isArchived`), **Streaming** (`isStreamingOnly && !isArchived`, status-only), **In iCloud only** (`isCloudOnlyOrphan`, "Locate…" picker), **Removed free books** (`isArchived && isFreeBook`, "Stream"). Swipe-to-delete on own rows = the **only** permanent cloud-delete path.
- **`ICloudBackupBadge`** — "Backed up to iCloud" affordance (cover overlay + detail inline) whenever `IcloudSyncGate.isEnabled()`. NSPersistentCloudKitContainer has no per-object synced flag, so this is an honest *static* badge (sync on ⇒ synced-store records are backed up), gated so it never promises backup to non-subscribers.
- **Delete copy is subscription-aware** — `ContentView`'s delete dialog branches all six paths (streaming-only / downloaded-free / own × sync-on/off) on `IcloudSyncGate.isEnabled()`. Subscriber own-book delete = single non-destructive **"Remove from this iPhone"** (drops local audio, keeps iCloud backup; deliberately no second local option). Non-subscribers keep the two-option hard delete ("Remove from App" / "Also Delete Files").
- **`isStreamingOnly` tiebreaker** — excludes own-book orphans (`!isDownloaded && !isFreeBook`) so they land in Cloud Library instead of being treated as streaming books.

### CarPlay

- `CarPlaySceneDelegate` → `CarPlayCoordinator` (templates, now-playing, moment saving, legacy seed catalog browsing)
- `CarPlayVoiceSearch` — hands-free dictation (Speech framework), auto-stops on silence
- `VoiceSearchPermissions.status` — synchronous mic + speech authorization check for the CarPlay path; voice search refuses with an info alert when not granted, because permission prompts **cannot** appear on the CarPlay screen. The onboarding Permissions scene is the only proactive request point (launch-time priming removed). Don't add permission requests that can fire only on CarPlay.
- `AppDelegate` — background URL session handler + CarPlay scene registration

### Widgets

Continue Listening lives in `PagelessDownloadActivity/` alongside the download Live Activity. Small/medium Home Screen and rectangular/circular Lock Screen widgets read only `continue-listening.json` and a ≤300px cover JPEG from `group.andreibaludev.Pageless`, never SwiftData. `ContinueListeningSnapshotWriter` writes at playback saves, pause/book change/finish and library removal, throttling periodic writes and timeline reloads to 30 seconds. Generated artwork comes from `GeneratedCoverView.renderImage` in the app. `unpaged://resume` and the medium `PlayLatestBookIntent` use the app’s pending-intent playback path; empty widgets open `unpaged://library`. DEBUG previews cover all four families.

### Siri / App Intents

`AudiobookIntents.swift` — `PlayLatestBookIntent` via `UnpagedAppShortcuts` ("Play Latest Book"). The shortcut writes a UserDefaults flag; `PagelessApp` consumes it on `scenePhase == .active`.

## Settings & Preferences

`@AppStorage` keys typed via enums in `PlaybackSettings.swift` (all `CaseIterable, Identifiable`): `LibrarySortOption`, `ResumeBacktrackOption`, `SkipIntervalOption`, `MomentBacktrackOption`, `SleepTimerOption`.

**Appearance** — `AppAppearance` (System / Light / Dark, key `appAppearance`; the legacy `forceDarkMode == true` migrates to Dark at launch). `PagelessApp` applies it with `.appAppearance(_:)`, which sets `overrideUserInterfaceStyle` on the scene's windows so sheets and covers follow. Don't use `.preferredColorScheme` for it: `nil` meant "follow system" (the old toggle did nothing on a dark phone), and SwiftUI doesn't restore the system scheme after `.dark` → `nil` until relaunch.

## Key Patterns

- **MVVM**: views own `@Query` / `@AppStorage` / UI state; ViewModels own business state + async workflows; services stateless + injectable (exceptions: `AudioPlayerManager`, `AudioEqualizerService`, `SamplePlayer`, `NetworkMonitor`). Pass `modelContext` explicitly to ViewModels/services.
- **Security-scoped file access**: always pair `startAccessingSecurityScopedResource` with a release path (see `LibraryViewModel.releaseSecurityScopedAccess()`).
- **Async bridging**: `withCheckedContinuation` / `withCheckedThrowingContinuation` for completion-handler APIs (Speech).
- **AI isolation**: `AppleIntelligenceCapability` guards UI visibility; ViewModels catch service errors and fall back gracefully. On iOS 18 it hard-returns `.unsupportedDevice` / `false` so AI surfaces never render.
- **Streaming vs downloaded**: `Audiobook.isStreamingOnly` is load-bearing — anything touching the on-disk path must check it. Promotion to downloaded goes through `LibriVoxDownloadService`.
- **Cover fallback**: any cover-art view must fall through to `GeneratedCoverView(title:)` when `coverArtData == nil` — never gradient + SF Symbol. `NowPlayingUpdater` mirrors this for lock screen / CarPlay artwork via `GeneratedCoverView.renderImage(title:side:)` with a `[title: UIImage]` cache.
- **Now-Playing metadata** (`NowPlayingUpdater.update`): track title → `MPMediaItemPropertyTitle` (use `track.displayTitle`), book title → `MPMediaItemPropertyAlbumTitle` (never concatenate the author into it), author → `MPMediaItemPropertyArtist`. Always set `MPNowPlayingInfoCenter.default().playbackState` after writing `nowPlayingInfo` — Siri uses it to route pause/resume intents.
- **Title display / rename propagation**: every playback surface (`PlayerView` big title, `NowPlayingUpdater` lock screen + CarPlay now-playing) reads `AudioTrack.displayTitle`, never raw `track.title`. For single-track books `displayTitle` falls back to the renamable `Audiobook.title` (lone track titles are file-metadata noise; `commitRename` writes only `audiobook.title`). Multi-track keeps per-chapter titles. `MiniPlayerBar` shows the book title and drops the duplicate single-track chapter line (`miniSecondaryLine`). Keep rename display-side — do **not** mutate `AudioTrack.title` rows on rename. CarPlay chapter-list rows still show raw per-track `title`.

## Testing

These rules apply to both iOS and Android:

- Never write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, first write down all the ways it could fail, then write the code. Write the isolated tests before the implementation, using that failure analysis.
- Keep an isolated test only when it catches a concrete bug the E2E assertions miss. Name that failure and the E2E coverage gap. Assertions that only repeat constructor defaults, getters, copied constants, mock-call bookkeeping or behavior already asserted by E2E do not justify a unit test.
- E2E evidence must include the exact rerun command, source revision and working-tree patch, device/runtime, fixture setup and machine-readable results. Include screenshots, recordings or exported state when needed to verify the feature's outcome. Preserve evidence outside Git and link it in the handoff or PR.

Run the native E2E suite and any retained isolated regression tests before a release build. For retained Swift Testing tests (`import Testing`), Codex uses `mcp__XcodeBuildMCP__test_sim` (or `test_device`) with `extraArgs: ["-parallel-testing-enabled", "NO"]`; Claude Code uses the `xcodebuild … test -parallel-testing-enabled NO` form from "Build & Run". `e2e/COVERAGE.md` records E2E scope and qualification boundaries.

- Reuse helpers in `PagelessTests/Mocks/` only for retained isolated regressions. Adding a protocol does not require adding a mock or a unit-test suite.
- **In-memory test containers: always pass `cloudKitDatabase: .none`** to `ModelConfiguration`. The default `.automatic` picks up the host app's CloudKit entitlement and fails CloudKit-shape validation. `SchemaCompatibilityTests.syncedSchemaSatisfiesCloudKitConstraints` is the one intentional `.private(...)` validation, via a file-backed temp store.
- **Hold the container in a local**: `let container = try makeContainer(); let context = container.mainContext` — never `try makeContainer().mainContext` (container deallocates; first fetch crashes the host app).
- **Native E2E (`e2e/`)** — tester-army/e2e suite driving the real app on a dedicated `Unpaged e2e` simulator, with fake LibriVox/Audiobookshelf servers and the local StoreKit config. DEBUG-only launch hooks live in `App/E2EFixtures.swift`. Setup, hooks and the iOS 18 smoke filter: `e2e/README.md`; flow matrix and latest run: `e2e/COVERAGE.md`.
