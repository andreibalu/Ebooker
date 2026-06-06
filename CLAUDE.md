# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Identity

- **Marketing name (App Store / home screen)**: Unpaged
- **Xcode scheme**: `Pageless`
- **Source module folder**: `Pageless/`
- **Bundle identifier prefix**: `andreibaludev.Pageless`
- **Current marketing version**: see `VERSION` (1.2)

The three names are intentional historical layers — do not "fix" them. New user-facing copy should say "Unpaged".

## External-facing docs

The repo ships three markdown files that are hosted publicly (currently via GitHub Gist) and linked from the App Store listing:

- `support.md` — Support URL contents (FAQ, troubleshooting, contact)
- `privacy-policy.md` — Privacy Policy URL contents
- `EULA.md` — End User License Agreement (Apple standard EULA + IAP/subscription terms)

**Keep these in sync with the app.** Whenever a change touches any of the following, update the relevant file(s) in the same commit:

- Permissions requested (`Info.plist` `NS*UsageDescription` keys) → support + privacy
- Network behavior, third-party services, or data collected → `privacy-policy.md`
- AI features, IAP terms, trial mechanics → all three (EULA §3 carries subscription/IAP terms)
- Supported devices, minimum iOS version (`IPHONEOS_DEPLOYMENT_TARGET`, `TARGETED_DEVICE_FAMILY`) → `support.md`
- New user-visible features that warrant a FAQ entry → `support.md`
- Contact email or developer name → all three (use the same "Andrei Baluta" spelling everywhere)

After editing, remind the user to push the new content to their public Gist(s) — the repo files are the source of truth, but the App Store points to the Gist URLs.

## Build & Run

Use XcodeBuildMCP tools for all build/run operations:

- **Build & run on device**: `mcp__XcodeBuildMCP__build_run_device` (scheme: `Pageless`)
- **Build only**: `mcp__XcodeBuildMCP__build_device`
- **Run tests**: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]` (Mac can't handle parallel destinations)
- **Clean**: `mcp__XcodeBuildMCP__clean`

Only device tools are enabled in this project's MCP profile — there is no `*_sim` variant.

Always call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/simulator settings before building.

**Device target**: Always build and run on **Andrei's iPhone 15 Pro** — identifier `00008130-000471A80C81001C` (UDID `BAE98D59-834B-5B20-8E9A-8943DCE6F7FD`). Use `mcp__XcodeBuildMCP__build_run_device` / `mcp__XcodeBuildMCP__build_device` instead of simulator tools. Use the `xcode-device-build` skill if needed for device setup. Apple Intelligence (`FoundationModels`) only runs on 15 Pro / 16+ hardware, so the simulator can't exercise AI surfaces.

External packages: **none.** All code uses native Apple frameworks only (AVFoundation, MediaToolbox, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, Intents, CarPlay, Network). RevenueCat (`purchases-ios-spm`) was previously bundled for observer-mode purchase analytics but has been **removed** — the SPM package is gone and every call site is commented out (search `// RevenueCat disabled` in `AppDelegate`, `AIEntitlementStore`, `ICloudSubscriptionStore`). Purchases are StoreKit-only. See "In-App Purchases" below for how to re-enable it.

## Info.plist Highlights (App Store relevant)

- `CFBundleDisplayName`: `Unpaged`
- `ITSAppUsesNonExemptEncryption`: `false`
- `NSMicrophoneUsageDescription` — for CarPlay voice search
- `NSSpeechRecognitionUsageDescription` — for transcription, AI moment naming, and CarPlay voice search
- `UIBackgroundModes`: `audio`
- Two scene roles registered: `UIWindowScene` (default) and `CPTemplateApplicationScene` → `CarPlaySceneDelegate`
- Orientations: portrait + both landscapes on iPhone; all four on iPad
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0` (`TARGETED_DEVICE_FAMILY = 1` keeps it iPhone-only). AI features (`FoundationModels`) are gated `@available(iOS 26, *)` and runtime-checked, so the binary installs and runs on iOS 18+ with the AI surface auto-hidden when below iOS 26.

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers (CarPlay is the one exception: `CarPlayCoordinator`).

### Folder Structure

Navigation map only — per-file detail lives in the topical sections below (Data Layer,
ViewModels, Services, Feature Systems). Non-obvious hints kept inline; self-evident files listed bare.

```
Pageless/
├── App/
│   ├── PagelessApp.swift          @main; ModelContainer, scene wiring, voice-permission priming, Siri handoff
│   ├── AppDelegate.swift          Split ModelContainer (synced+local); re-runs orphan detection on CloudKit import batches
│   └── CarPlaySceneDelegate.swift
├── AppIntents/AudiobookIntents.swift   `PlayLatestBookIntent` + `UnpagedAppShortcuts`
├── Configuration/
│   ├── AIProductID.swift          `AIProductID.unlock` + `ICloudSyncProductID.monthly`
│   └── Products.storekit          Local StoreKit test config
├── Models/                        Audiobook, AudioTrack, Moment, MomentEnums, PlaybackSettings,
│                                  EqualizerSettings, LibriVoxBook, CachedLibriVoxTrack,
│                                  ReadingSession, ReadingStats, FreeBookCatalogEntry (legacy)
├── ViewModels/                    Player, AudiobookDetail, Library, BrowseLibriVox,
│                                  LibriVoxBookDetail, StreamedBookDownload  (see ViewModels table)
├── Views/                         ContentView (root tabs + per-tab sort + header iCloud button),
│   │                              Player, AudiobookDetail, AudiobookCard/TrackRow, MiniPlayerBar,
│   │                              Moment{Row,EditSheet,FilterSheet}, ImportAudiobookSheet,
│   │                              Settings/AISettings/ICloudSettings, CoverCropView, CloudLibraryView,
│   │                              ICloudBackupBadge, RestoreMatchSheet, GeneratedCoverView, EqualizerSheet
│   ├── FreeBooks/                 BrowseLibriVoxView, LibriVoxBookDetailView, LibriVoxBookRow
│   ├── ReadingStats/              ReadingActivityCard, ReadingStatsView, ReadingStatsSections, ReadingHeatmap
│   └── Onboarding/                OnboardingFlowView (host), OnboardingScenes (6 scenes + widgets), OnboardingTheme (tokens/primitives)
├── Services/
│   ├── Protocols/                 TranscriptionProviding, MomentAnalyzing, AudioExtracting,
│   │                              RecapProviding, FreeBookDownloading
│   │                              (MomentAnalyzing/RecapProviding also hold the iOS<26 Unavailable… fallbacks)
│   ├── AudioPlayerManager.swift   Central playback state; owns `equalizer: AudioEqualizerService`
│   ├── (playback)                 PlaybackPersistence, NowPlayingUpdater, AudiobookSavedProgressResume
│   ├── (import/AI)                LibraryImportService, TranscriptionService, MomentNamingService²⁶,
│   │                              RecapService²⁶, AudioExtractionService, AppleIntelligenceCapability
│   ├── (stats)                    ReadingSessionRecorder, ReadingActivitySeeder (DEBUG-only)
│   ├── (EQ)                       AudioEqualizerService, EqualizerTap (C MTAudioProcessingTap)
│   ├── (LibriVox)                 LibriVoxAPIClient, LibriVoxCatalogSync, LibriVoxDownloadService,
│   │                              StreamingLibraryService, SamplePlayer, NetworkMonitor
│   ├── (CarPlay/legacy)           CarPlayCoordinator, CarPlayVoiceSearch, VoiceSearchPermissions,
│   │                              FreeBookCatalogService, FreeBookDownloadService
│   ├── (IAP)                      AIEntitlementStore, ICloudSubscriptionStore, IcloudSyncGate
│   ├── (iCloud sync)              FingerprintBackfillService, OrphanDetectionService, OrphanRestoreService
│   └── OnboardingManager.swift
└── Utilities/                     TimeFormatter, BookDescriptionFormatting, Color+Theme (`amber` accent)
```
`²⁶` = `@available(iOS 26, *)`.

PagelessTests/ — Swift Testing. Mocks/ (one per protocol service), ModelTests/, ServiceTests/,
  ViewModelTests/. SchemaCompatibilityTests validates CloudKit constraints. PagelessUITests/ — launch + UI tests.

## Data Layer (SwiftData)

**Five models** registered in the `ModelContainer` (see `AppDelegate.swift`): `Audiobook`, `AudioTrack`, `Moment`, `LibriVoxBook`, `ReadingSession`.

Audio files for downloaded books are stored at `Application Support/Audiobooks/[UUID]/`. Cover images use SwiftData external storage. Streaming-only books store remote URLs on `AudioTrack` and have `Audiobook.isDownloaded == false`.

Model field listings live in the model source files (`Models/`). Non-obvious points: `Audiobook` cascade-deletes its `tracks[]` + `moments[]`; `AudioTrack.contentFingerprint` (SHA-256 hex) drives iCloud orphan matching; `Moment` stores AI fields (categories/quoteLine/characters/mood) JSON-serialized; `ReadingSession` snapshots book metadata (bookID/title/author/isFreeBook) so stats survive book deletion.

**Schema evolution**: New columns use private backing fields with computed getters/setters (e.g., `_isFavorite`, `_isFreeBook`, `_isDownloaded`, `_progressRecap*`, `_eqBandGainsJSON`, `_eqPresetRaw`, `_contentFingerprint`) for SwiftData lightweight migration. All post-launch fields are nullable on disk and given safe defaults in the computed accessor.

**CloudKit schema constraint**: CloudKit does not support `@Attribute(.unique)` or relationship `originalName` without explicit inverses. All four synced models (`Audiobook`, `AudioTrack`, `Moment`, `ReadingSession`) have explicit relationship inverses and no `.unique` attributes. `LibriVoxBook` (local store only) retains `.unique` on its `id` field. Do not add `.unique` to any synced model.

## Central State: `AudioPlayerManager`

`AudioPlayerManager` (ObservableObject) is the single source of truth for all playback state, injected via `@EnvironmentObject`. It exposes its `equalizer: AudioEqualizerService` as a separate `@EnvironmentObject` so views can bind to EQ controls without going through the player.

Responsibilities:
- AVPlayer orchestration, track queuing, background audio modes
- Builds per-item `AVAudioMix` via `AudioEqualizerService.makeAudioMix(for:)` so the EQ tap runs in the audio pipeline
- Delegates persistence to `PlaybackPersistence` (progress saves, high-water mark, seek penalty)
- Delegates remote commands to `NowPlayingUpdater` (Control Center, headphone controls, CarPlay now-playing)
- 1-second periodic time observer for live progress updates; feeds `ReadingSessionRecorder.tick(...)` to attribute wall-clock listening to the current book
- Flushes the `ReadingSessionRecorder` on pause, track change, audiobook change, app background, and book finish so partial chunks aren't lost
- Handles streaming items (remote `AudioTrack` URLs) and local file items uniformly

## ViewModels

All ViewModels are `@MainActor @Observable`. Views create them with `@State`. Services are injected via initializers with protocol types (default concrete implementations provided so views can call `ViewModel()` without arguments).

| ViewModel | Key State | Services |
|-----------|-----------|----------|
| `PlayerViewModel` | `pendingMomentTime`, `momentNameInput`, `pendingCategories`, `pendingCharacters`, `pendingMood`, `pendingQuoteLine`, smart-save warning state | `TranscriptionProviding`, `MomentAnalyzing`, `AudioExtracting` |
| `AudiobookDetailViewModel` | `filterCategories`, `filterCharacters`, `filterMoods`, `isLoadingRecap`, `recapText`, `recapProgressHeadline` | `TranscriptionProviding`, `AudioExtracting`, `RecapProviding` |
| `LibraryViewModel` | `pendingImport`, `urlsHoldingSecurityAccess`, `deleteCandidate`, `renameCandidate` | `FreeBookDownloading` (legacy seed catalog) |
| `BrowseLibriVoxViewModel` | `searchQuery`, `searchResults`, `syncState`, `activeDownloads`, `featuredBooks`, language/genre/duration filters | `LibriVoxAPIClient`, `LibriVoxCatalogSync` (via SwiftData) |
| `LibriVoxBookDetailViewModel` | `downloadState`, `addToLibraryState`, `isAlreadyInLibrary` | `LibriVoxDownloadService`, `StreamingLibraryService` |
| `StreamedBookDownloadViewModel` | `state` (idle/downloading/done/error) | `LibriVoxDownloadService` |

## Services

Protocol implementations are typically `struct`. `LibraryImportService` is a concrete `enum` with static methods. Catalog/sync services are typically `enum` with static methods (`LibriVoxAPIClient`, `LibriVoxCatalogSync`, `FreeBookCatalogService`). `SamplePlayer` and `NetworkMonitor` are singletons.

| Protocol | Implementation | Framework |
|----------|---------------|-----------|
| `TranscriptionProviding` | `TranscriptionService` | Speech |
| `MomentAnalyzing` | `MomentNamingService` (iOS 26+) · `UnavailableMomentAnalyzer` (iOS 18 fallback) | FoundationModels |
| `RecapProviding` | `RecapService` (iOS 26+) · `UnavailableRecapProvider` (iOS 18 fallback) | FoundationModels |
| `AudioExtracting` | `AudioExtractionService` | AVFoundation (AVAssetExportSession) |
| `FreeBookDownloading` | `FreeBookDownloadService` | URLSession (background) — legacy seed catalog |

## AI & On-Device Intelligence

- `MomentNamingService: MomentAnalyzing` — AI moment analysis: name, note, categories, quoteLine, characters, mood (`@available(iOS 26, *)`)
- `RecapService: RecapProviding` — generates `RecapGenerationResult` (recap text + optional `progressHeadline`) (`@available(iOS 26, *)`)
- `TranscriptionService: TranscriptionProviding` — Speech framework wrapper with `withCheckedContinuation` bridge
- `AppleIntelligenceCapability` — runtime detection for showing/hiding AI UI buttons; iOS-18-safe (internal `if #available(iOS 26, *)` branches)
- `AIEntitlementStore` — StoreKit 2: trial uses tracking + IAP unlock (`AIProductID`). Entitlement state is owned entirely by StoreKit (`Transaction.currentEntitlements`); the app reads it directly. (RevenueCat observer-mode mirroring was removed — the `recordPurchase`/`syncPurchases` calls remain commented out for future re-enable.)

### In-App Purchases (two products)

The app sells **two IAPs**, both StoreKit-owned. The app gates on StoreKit directly — it reads `Transaction.currentEntitlements`, with no third-party purchase SDK involved:

| Product | Store ID | Type | Owner store |
|---------|----------|------|-------------|
| AI Features unlock | `andreibaludev.Pageless.ai_unlock` | Non-consumable | `AIEntitlementStore` |
| iCloud Sync | `andreibaludev.Pageless.icloudsync.monthly` | Auto-renewable monthly ($0.99, **no free trial**) | `ICloudSubscriptionStore.shared` |

- **`ICloudSubscriptionStore`** mirrors `AIEntitlementStore`'s shape: `loadProduct()` (`Product.products(for:)`), `refreshEntitlements()` (`Transaction.currentEntitlements`), `purchase()`, `restorePurchases()`, and a `Transaction.updates` listener. It's a **singleton** because `AppDelegate.init` reads `isSubscribedAtLaunch()` (a UserDefaults cache) when choosing the SwiftData CloudKit database before SwiftUI env objects exist.
- **No free trial.** `introOfferDisplay` returns nil unless the App Store product actually carries a `.freeTrial` introductory offer, so the UI shows "Subscribe" + "$0.99/month" rather than promising a trial that ASC isn't configured for. Don't reintroduce a hardcoded trial string.
- **Reachability (Apple 3.1.1).** The iCloud Sync purchase must be reachable in the reviewed build: Settings → "iCloud Sync" hero card (shown **unconditionally** in `SettingsView.unlockSection`) → `ICloudSettingsView` → "Subscribe". It is **not** hidden behind an iCloud sign-in. A prior build was rejected under 3.1.1 for shipping the subscription product without an in-app purchase path.
- **RevenueCat (removed).** RC ran in observer mode purely for dashboard metrics; the app never gated on it. To re-enable: re-add the `purchases-ios-spm` package and uncomment the `// RevenueCat disabled` blocks (Release-only / `if Purchases.isConfigured`-guarded) in `AppDelegate`, `AIEntitlementStore`, `ICloudSubscriptionStore`, then restore the RC disclosures in `privacy-policy.md`. Server-side config still exists (project `proj0c83cb7e`, app `app5156e9dfbb`). End-to-end verification needs a TestFlight build (local `Products.storekit` receipts can't be validated by RC's backend).
- AI features are isolated behind protocols; app works fully without Apple Intelligence
- **iOS 18 deployment-target rule.** The deployment target is `18.0` but `FoundationModels` is iOS 26-only. The two service types (`MomentNamingService`, `RecapService`) carry `@available(iOS 26, *)`; `MomentAnalysis`/`MomentNamingError`/`RecapError`/`RecapGenerationResult` live in the protocol files so iOS-18 callers and mocks can use them without availability gating. ViewModel default initializers (`PlayerViewModel`, `AudiobookDetailViewModel`) branch on `if #available(iOS 26, *)` to construct the real service vs. the `Unavailable…` no-op stub. Any new AI-only API must follow the same pattern — never reference `FoundationModels` symbols outside an `@available`-gated type or an `if #available(iOS 26, *)` block.
- **`SystemLanguageModel.default` has a ~4096-token budget shared between input and output.** When designing a `@Generable` struct, order fields so cheap structured outputs (single-token enums, short arrays) come first and the longest prose field is last — the model generates fields in declaration order and the trailing field is what gets clipped when the budget runs out. Post-process any free-text field to handle mid-sentence truncation (see `MomentNamingService.trimToCompleteSentences` / `sanitizedQuoteLine`); never trust the model to honor word/sentence-count guides on the long tail.

## Feature Systems

### Free Books — two parallel systems

The app contains **two independent free-book paths** that coexist by design:

1. **LibriVox catalog (primary, iPhone)** — 20,000+ books from librivox.org. Cached locally in `LibriVoxBook` via `LibriVoxCatalogSync` (24h incremental sync). UI is the "Free Books" tab in `ContentView`, driven by `BrowseLibriVoxView` → `LibriVoxBookDetailView`. Supports:
   - **Add to Library (streaming)** via `StreamingLibraryService` — creates an `Audiobook` with `isDownloaded == false` and remote URLs on each `AudioTrack`. No files written. Requires network at playback time.
   - **Download** via `LibriVoxDownloadService` — fetches all tracks, creates a downloaded `Audiobook` tagged as a free book (`isFreeBook = true`, `catalogId = book.id`, and each `AudioTrack` keeps its `remoteURLString`) so it shares the same iCloud identity as a streaming entry and can be matched/re-streamed by id after removal. Also used by `StreamedBookDownloadViewModel` to promote an already-added streaming book to downloaded.
   - **Sample preview** via `SamplePlayer` — 20s preview of a track without committing.
   - **Network gating** — `NetworkMonitor.shared.isConnected` checked before sample play, sync, and streaming.
   - **Covers are intentionally not fetched.** LibriVox cover URLs are unreliable, so both `LibriVoxDownloadService` and `StreamingLibraryService` always set `coverArtData = nil` and let `GeneratedCoverView` render the letter template. Don't reintroduce remote cover fetches here.

2. **Legacy seed catalog (CarPlay)** — `FreeBookCatalogService` exposes 5 hand-picked Internet Archive classics. Downloaded via `FreeBookDownloadService` (background URLSession with published `downloadProgress`, `activeDownloads`, `downloadErrors`). Consumed only by `CarPlayCoordinator` and `LibraryViewModel`. **Do not extend this path for new iPhone features — use the LibriVox path.**

### Reading Activity & Stats

- `ReadingSession` (SwiftData `@Model`) is the only persisted row — one chunk = one book × one wall-clock hour bucket, with the book's metadata snapshotted so deletion of a book doesn't erase the history.
- `ReadingSessionRecorder` (`@MainActor`) is owned by `AudioPlayerManager` and ticked from its 1-second periodic time observer while `isPlaying`. Continuous play emits chunks every ~5 minutes; pause / track change / book change / app background / finish all flush whatever's accumulated. Chunks shorter than 30s are dropped as scrub noise.
- `ReadingStats.compute(sessions:booksFinished:)` is a pure aggregate over `[ReadingSession]` → totals, best day/hour/dow, streaks, top author, longest book, free-book share, per-day activity map. No persistence; recomputed when the `@Query` of sessions changes.
- The Favorites tab pins `ReadingActivityCard` above the grid (only when `stats.hasAnyActivity`); tapping pushes `ReadingStatsView` with a zoom transition that morphs out of the card's heatmap. The full view composes `ReadingStatsSections` (hero, totals, best day, polar best-time-of-day chart, longest book, streaks, metrics, free-books ring) inside a `LazyVStack` with `revealOnAppear` and `CountUpText` choreography.
- `ReadingHeatmap` + `HeatmapPalette` (currently `.amber`) are the shared visual primitive used by both the card and the full view.
- `ReadingActivitySeeder` is wrapped in `#if DEBUG` and seeds 113 days of synthetic activity for iterating on the stats screen without burning real listening time. Don't ship a code path that calls it from release builds.

### Equalizer (per-book)

- `EqualizerSettings` defines the data model: 5 bands (60Hz / 250Hz / 1kHz / 4kHz / 14kHz), presets (flat, voiceBoost, bassBoost, trebleBoost, podcast, custom), preamp 0–12 dB, band gain ±12 dB
- `EqualizerTap` is a C-level `MTAudioProcessingTap` running biquad filters + a soft limiter on the realtime audio thread; coefficients updated under `os_unfair_lock`
- `AudioEqualizerService` (`ObservableObject`) holds the live `@Published` state, persists it to the current `Audiobook.equalizerConfiguration`, and builds the `AVAudioMix` injected into each `AVPlayerItem`
- `EqualizerSheet` is the user-facing UI; reads/writes via `@EnvironmentObject AudioEqualizerService`

### Onboarding

A **standalone welcome flow** shown once on first launch (and on demand via Settings → "Reset Onboarding"). It replaced the old phase-based spotlight walkthrough — there is no longer any `OnboardingStep` / `SpotlightOverlayView` / `.spotlightTarget()` machinery; don't reintroduce it.

- **`OnboardingManager`** — now just a completion gate: `isComplete` (persisted to `onboardingComplete`), `complete()`, `reset()`. Init migrates legacy users — anyone with the old `onboardingPhase == 3` (completed) is treated as complete so they don't re-see onboarding. `ContentView` presents `OnboardingFlowView` via `.fullScreenCover` while `!isComplete`.
- **`OnboardingFlowView`** (host) — a paged vertical `ScrollView` (`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`) of six full-screen scenes with a floating right-edge progress-dot rail. The active scene index drives each scene's reveal/count-up/stagger animations (triggering on `.onAppear` is wrong here — paged rows instantiate before they center).
- **Preference controls bind live to the app's existing `@AppStorage` keys** (`resumeBacktrackSeconds`, `skipBackSeconds`, `skipForwardSeconds`, `momentBacktrackSeconds`) — so persistence is automatic, the scene-6 summary shares one source of truth, and the choice is freely reversible. "Open Library" calls `onboarding.complete()` and routes into the chosen home tab (free → Free Books, own → All Books); it does **not** persist a home-tab override, so relaunched/legacy users still land on Favorites.
- **Scenes 4 (Apple Intelligence) and 5 (iCloud Sync) are informational only** — no paywall, no toggles. Don't wire purchase/sync state into them.
- **`OnboardingScenes`** holds the six scenes + widgets (choice cards, drag `OBRulerPicker`, chip rows, stepper, `OBHeatmap`, moment-naming card, `OBSyncGraphic`, summary). **`OnboardingTheme`** holds the design tokens (`OB.*` colors, `OBMotion`), type primitives (`OBEyebrow`/`OBHeadline`/`OBSub`/`obSerif`), and the `obReveal` / `obParallax` modifiers.
- **Requirement: identical on every device/iOS version.** Fixed point sizes throughout, a fixed 402pt content column centered on wider screens, a `.dynamicTypeSize(.large)` clamp at the root (never Dynamic Type), and the app's own light/dark theme via `preferredColorScheme(forceDarkMode ? .dark : nil)`. All animations honor Reduce Motion.

### iCloud Sync

Library metadata, progress, moments, EQ configuration, and reading sessions sync across devices via CloudKit private database. Audio files are not synced — they must be re-acquired on each device. **iCloud Sync is a paid feature** — an auto-renewable monthly subscription ($0.99, no trial); see "In-App Purchases" above.

- **`IcloudSyncGate`** — single decision point: requires an active subscription (`ICloudSubscriptionStore.isSubscribedAtLaunch()`) AND the `iCloudSyncEnabled` UserDefaults toggle AND `FileManager.ubiquityIdentityToken`. When any is false, `AppDelegate` builds the SwiftData container with `.none` database. Container ID: `iCloud.andreibaludev.Pageless`.
- **Split `ModelContainer`** — `AppDelegate` creates two configurations: `"synced"` (Audiobook/AudioTrack/Moment/ReadingSession → CloudKit private DB when enabled) and `"local"` (LibriVoxBook → never synced).
- **Orphan detection** — `OrphanDetectionService` runs at launch and after every `NSPersistentCloudKitContainer.eventChangedNotification` import event. Any book marked `isDownloaded = true` whose storage folder is absent gets flipped to `isDownloaded = false`, making it a recoverable orphan.
- **Fingerprinting** — `LibraryImportService` computes a SHA-256 content fingerprint (truncated to 16 bytes of audio data) for each imported track, stored on `AudioTrack.contentFingerprint`. `FingerprintBackfillService` backfills existing tracks on first launch after upgrade.
- **Restore on re-import (own books)** — when a user imports files on a new device, `LibraryViewModel` calls `OrphanRestoreService.findMatch` to fingerprint-compare against orphan candidates. A match triggers `RestoreMatchSheet` ("Restore from iCloud" / "Add as new"). `OrphanRestoreService.adopt` rewrites the orphan's `AudioTrack` records in-place, preserving all moments/progress/EQ.
- **Match by id (free books)** — free books carry no file fingerprint, so they match on `catalogId` instead. Removing a free book with sync on calls `LibraryImportService.archiveFreeBook` (drops files, sets `isArchived = true`, keeps the synced record + remote URLs). Re-adding the same book from the Free Books tab — streaming **or** downloading — calls `OrphanRestoreService.fetchFreeBackup(catalogId:)`; a hit raises a confirmation in `LibriVoxBookDetailView` ("Import from iCloud" reuses/re-downloads the backup in place, "Add as New" creates a fresh copy). If the user added as new, `AudiobookDetailView`'s iCloud button restores later via `OrphanRestoreService.restoreFreeBackup` (cloud-wins, no files to copy). `isArchived` is the free-book analogue of an own book's `!isDownloaded` orphan state — needed because free `!isDownloaded` alone is ambiguous (active streaming vs removed).
- **`CloudLibraryView`** — the full iCloud Library, not just orphans: every book the user has ever added is always listed so backup is visibly verifiable. Reachable two ways: Settings → iCloud Library, **and** a dedicated iCloud button in the main library header that is shown only when `ICloudSubscriptionStore.isSubscribedAtLaunch()` (it replaced the old header sort button — sort moved to per-tab chevron menus). Four mutually-exclusive buckets — **On this iPhone** (`isDownloaded && !isArchived`, own + free), **Streaming** (`!isDownloaded && isFreeBook && !isArchived`, status-only), **In iCloud only** (`!isDownloaded && !isFreeBook`, "Locate…" picker), **Removed free books** (`isArchived && isFreeBook`, "Stream"). Swipe-to-delete on own rows is the **only** permanent cloud-delete path.
- **`ICloudBackupBadge` (sync assurance)** — a subtle "Backed up to iCloud" affordance shown on each book (cover overlay + detail inline) whenever `IcloudSyncGate.isEnabled()`. NSPersistentCloudKitContainer exposes no per-object "synced" flag, so this is an honest *static* badge (sync on ⇒ every synced-store record is backed up), not a real-time pulse — gated on subscription+toggle so it never promises backup to non-subscribers.
- **Delete copy is subscription-aware** — `ContentView`'s delete dialog branches all six paths (streaming-only / downloaded-free / own × sync-on/off) on `IcloudSyncGate.isEnabled()`. Subscriber own-book delete is a single non-destructive **"Remove from this iPhone"** (soft-delete: drops local audio, keeps the iCloud backup); there is intentionally no second local option (a "files-on-disk-but-not-in-library" state has no sensible meaning). Non-subscribers keep the two-option hard delete ("Remove from App" / "Also Delete Files").
- **`isStreamingOnly` tiebreaker** — `Audiobook.isStreamingOnly` excludes own-book orphans (`!isDownloaded && !isFreeBook`) so they appear in Cloud Library, not treated as streaming books.

### CarPlay
- `CarPlaySceneDelegate` — connects CarPlay scene to `CarPlayCoordinator`
- `CarPlayCoordinator` — full CarPlay UI templates, now-playing, moment saving, browsing the legacy seed catalog
- `CarPlayVoiceSearch` — hands-free dictation over the Speech framework, auto-stops on silence
- `VoiceSearchPermissions` — primes mic + speech permissions on iPhone at app launch (`PagelessApp.task`) so CarPlay never has to surface a permission prompt mid-drive (it can't)
- `AppDelegate` — background URL session handler + CarPlay scene registration

### Siri / App Intents
- `AudiobookIntents.swift` — `PlayLatestBookIntent` exposed via `UnpagedAppShortcuts: AppShortcutsProvider` ("Play Latest Book"). Triggered shortcut writes a UserDefaults flag and `PagelessApp` consumes it on `scenePhase == .active`.

## Settings & Preferences

`@AppStorage` keys typed via enums in `PlaybackSettings.swift`:
- `LibrarySortOption` — recent, title, author, duration, dateAdded
- `ResumeBacktrackOption`, `SkipIntervalOption`, `MomentBacktrackOption`, `SleepTimerOption`

All enums are `CaseIterable, Identifiable`.

## Key Patterns

- **MVVM**: Views own `@Query`, `@AppStorage`, UI state. ViewModels own business state and async workflows. Services are stateless and injectable (with exceptions for `AudioPlayerManager`, `AudioEqualizerService`, `SamplePlayer`, `NetworkMonitor`).
- **Dependency injection**: Initializer injection on ViewModels with protocol-typed services; default implementations provided so views can call `ViewModel()` without arguments.
- **SwiftData queries**: Use `@Query` in views; pass `modelContext` explicitly to ViewModels/services.
- **Security-scoped file access**: For user-imported files, always pair `startAccessingSecurityScopedResource` with a release path (see `LibraryViewModel.releaseSecurityScopedAccess()`).
- **Async bridging**: Use `withCheckedContinuation` / `withCheckedThrowingContinuation` when bridging completion-handler APIs (Speech framework).
- **AI isolation**: `AppleIntelligenceCapability` guards UI visibility; ViewModels catch service errors and fall back gracefully. On iOS 18 the helper hard-returns `.unsupportedDevice` / `false` so AI surfaces never render.
- **Schema migration**: Private backing field pattern (`_fieldName`) with computed getter/setter for post-launch columns; new fields nullable on disk.
- **Streaming vs downloaded**: Treat `Audiobook.isStreamingOnly` as load-bearing — anything that touches the on-disk path must check it. Promotion to downloaded goes through `LibriVoxDownloadService`.
- **Cover fallback**: Any view that displays cover art must fall through to `GeneratedCoverView(title:)` when `coverArtData == nil` — not a gradient + SF Symbol. `NowPlayingUpdater` mirrors this for lock screen / CarPlay artwork via `GeneratedCoverView.renderImage(title:side:)` with a `[title: UIImage]` cache so it doesn't re-render every periodic tick.
- **CarPlay permission constraint**: Mic + speech permission prompts cannot appear on the CarPlay screen, so `VoiceSearchPermissions.primeIfNeeded()` runs at iPhone launch. Don't add new permission requests that can fire only on CarPlay.
- **Now-Playing metadata convention** (`NowPlayingUpdater.update`): track title → `MPMediaItemPropertyTitle`, book title → `MPMediaItemPropertyAlbumTitle` (do NOT concatenate author into this), author → `MPMediaItemPropertyArtist`. Always set `MPNowPlayingInfoCenter.default().playbackState` after writing `nowPlayingInfo` — Siri uses it to route pause/resume intents.

## Testing

Tests use Swift Testing framework (`import Testing`). To run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]` (there is no `*_sim` variant — see Build & Run).

Mock implementations live in `PagelessTests/Mocks/`:
- `MockTranscriptionService`, `MockMomentAnalyzer`, `MockRecapService`, `MockAudioExtractor`, `MockFreeBookDownloadService`

All protocol-backed services have corresponding mocks for ViewModel tests. New LibriVox-path code is currently exercised through integration-style tests against SwiftData in-memory containers rather than via mocks — if you add a new protocol there, add a matching mock under `PagelessTests/Mocks/`.

**In-memory test containers**: always pass `cloudKitDatabase: .none` to `ModelConfiguration`. The default is `.automatic`, which on device picks up the host app's CloudKit entitlement and triggers CloudKit-shape validation that fails even with everything defaulted — the test bundle's view of the schema differs from production. `SchemaCompatibilityTests.syncedSchemaSatisfiesCloudKitConstraints` is the one place that intentionally exercises `.private(...)` validation, via a file-backed temp store.

**Hold the container in a local**: `let container = try makeContainer(); let context = container.mainContext` — never `try makeContainer().mainContext`. The container is released immediately and the mainContext crashes the host app at the first fetch.
