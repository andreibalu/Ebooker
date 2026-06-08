# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repo.

## App Identity

- **Marketing name (App Store / home screen)**: Unpaged
- **Xcode scheme**: `Pageless`
- **Source module folder**: `Pageless/`
- **Bundle identifier prefix**: `andreibaludev.Pageless`
- **Current marketing version**: see `VERSION` (currently 1.3)

Three names = intentional historical layers — no "fix". New user-facing copy say "Unpaged".

## External-facing docs

Repo ships three markdown files hosted publicly (currently via GitHub Gist), linked from App Store listing:

- `support.md` — Support URL contents (FAQ, troubleshooting, contact)
- `privacy-policy.md` — Privacy Policy URL contents
- `EULA.md` — End User License Agreement (Apple standard EULA + IAP/subscription terms)

**Keep in sync with app.** When change touches any below, update relevant file(s) same commit:

- Permissions requested (`Info.plist` `NS*UsageDescription` keys) → support + privacy
- Network behavior, third-party services, data collected → `privacy-policy.md`
- AI features, IAP terms, trial mechanics → all three (EULA §3 carries subscription/IAP terms)
- Supported devices, minimum iOS version (`IPHONEOS_DEPLOYMENT_TARGET`, `TARGETED_DEVICE_FAMILY`) → `support.md`
- New user-visible features warranting FAQ entry → `support.md`
- Contact email or developer name → all three (same "Andrei Baluta" spelling everywhere)

After edit, remind user push new content to public Gist(s) — repo files = source of truth, but App Store points to Gist URLs.

## Build & Run

Use XcodeBuildMCP tools for all build/run:

- **Build & run on device**: `mcp__XcodeBuildMCP__build_run_device` (scheme: `Pageless`)
- **Build only**: `mcp__XcodeBuildMCP__build_device`
- **Run tests**: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]` (Mac can't handle parallel destinations)
- **Clean**: `mcp__XcodeBuildMCP__clean`

Only device tools enabled in this MCP profile — no `*_sim` variant.

Always call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/simulator settings before building.

**Device target**: Always build + run on **Andrei's iPhone 15 Pro** — identifier `00008130-000471A80C81001C` (UDID `BAE98D59-834B-5B20-8E9A-8943DCE6F7FD`). Use `mcp__XcodeBuildMCP__build_run_device` / `mcp__XcodeBuildMCP__build_device` not simulator tools. Use `xcode-device-build` skill if needed for device setup. Apple Intelligence (`FoundationModels`) only runs on 15 Pro / 16+ hardware, so simulator can't exercise AI surfaces.

External packages: **none.** All code uses native Apple frameworks only (AVFoundation, MediaToolbox, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, Intents, CarPlay, Network). RevenueCat (`purchases-ios-spm`) was previously bundled for observer-mode purchase analytics but **removed** — SPM package gone, every call site commented out (search `// RevenueCat disabled` in `AppDelegate`, `AIEntitlementStore`, `ICloudSubscriptionStore`). Purchases StoreKit-only. See "In-App Purchases" below to re-enable.

## Info.plist Highlights (App Store relevant)

- `CFBundleDisplayName`: `Unpaged`
- `ITSAppUsesNonExemptEncryption`: `false`
- `NSMicrophoneUsageDescription` — for CarPlay voice search
- `NSSpeechRecognitionUsageDescription` — for transcription, AI moment naming, CarPlay voice search
- `UIBackgroundModes`: `audio`
- Two scene roles registered: `UIWindowScene` (default) and `CPTemplateApplicationScene` → `CarPlaySceneDelegate`
- Orientations: portrait + both landscapes on iPhone; all four on iPad
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0` (`TARGETED_DEVICE_FAMILY = 1` keeps iPhone-only). AI features (`FoundationModels`) gated `@available(iOS 26, *)` + runtime-checked, so binary installs + runs on iOS 18+ with AI surface auto-hidden below iOS 26.

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers (CarPlay one exception: `CarPlayCoordinator`).

### Folder Structure

Navigation map only — per-file detail in topical sections below (Data Layer,
ViewModels, Services, Feature Systems). Non-obvious hints inline; self-evident files listed bare.

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

**Five models** registered in `ModelContainer` (see `AppDelegate.swift`): `Audiobook`, `AudioTrack`, `Moment`, `LibriVoxBook`, `ReadingSession`.

Audio files for downloaded books stored at `Application Support/Audiobooks/[UUID]/`. Cover images use SwiftData external storage. Streaming-only books store remote URLs on `AudioTrack`, have `Audiobook.isDownloaded == false`.

Model field listings in model source files (`Models/`). Non-obvious points: `Audiobook` cascade-deletes its `tracks[]` + `moments[]`; `AudioTrack.contentFingerprint` (SHA-256 hex) drives iCloud orphan matching; `Moment` stores AI fields (categories/quoteLine/characters/mood) JSON-serialized; `ReadingSession` snapshots book metadata (bookID/title/author/isFreeBook) so stats survive book deletion.

**Schema evolution**: New columns use private backing fields with computed getters/setters (e.g. `_isFavorite`, `_isFreeBook`, `_isDownloaded`, `_progressRecap*`, `_eqBandGainsJSON`, `_eqPresetRaw`, `_contentFingerprint`) for SwiftData lightweight migration. All post-launch fields nullable on disk, given safe defaults in computed accessor.

**CloudKit schema constraint**: CloudKit not support `@Attribute(.unique)` or relationship `originalName` without explicit inverses. All four synced models (`Audiobook`, `AudioTrack`, `Moment`, `ReadingSession`) have explicit relationship inverses, no `.unique` attributes. `LibriVoxBook` (local store only) retains `.unique` on its `id` field. Do not add `.unique` to any synced model.

## Central State: `AudioPlayerManager`

`AudioPlayerManager` (ObservableObject) = single source of truth for all playback state, injected via `@EnvironmentObject`. Exposes its `equalizer: AudioEqualizerService` as separate `@EnvironmentObject` so views bind to EQ controls without going through player.

Responsibilities:
- AVPlayer orchestration, track queuing, background audio modes
- Builds per-item `AVAudioMix` via `AudioEqualizerService.makeAudioMix(for:)` so EQ tap runs in audio pipeline
- Delegates persistence to `PlaybackPersistence` (progress saves, high-water mark, seek penalty)
- Delegates remote commands to `NowPlayingUpdater` (Control Center, headphone controls, CarPlay now-playing)
- 1-second periodic time observer for live progress updates; feeds `ReadingSessionRecorder.tick(...)` to attribute wall-clock listening to current book
- Flushes `ReadingSessionRecorder` on pause, track change, audiobook change, app background, book finish so partial chunks not lost
- Handles streaming items (remote `AudioTrack` URLs) + local file items uniformly

## ViewModels

All ViewModels `@MainActor @Observable`. Views create them with `@State`. Services injected via initializers with protocol types (default concrete implementations provided so views call `ViewModel()` without arguments).

| ViewModel | Key State | Services |
|-----------|-----------|----------|
| `PlayerViewModel` | `pendingMomentTime`, `momentNameInput`, `pendingCategories`, `pendingCharacters`, `pendingMood`, `pendingQuoteLine`, smart-save warning state | `TranscriptionProviding`, `MomentAnalyzing`, `AudioExtracting` |
| `AudiobookDetailViewModel` | `filterCategories`, `filterCharacters`, `filterMoods`, `isLoadingRecap`, `recapText`, `recapProgressHeadline` | `TranscriptionProviding`, `AudioExtracting`, `RecapProviding` |
| `LibraryViewModel` | `pendingImport`, `urlsHoldingSecurityAccess`, `deleteCandidate`, `renameCandidate` | `FreeBookDownloading` (legacy seed catalog) |
| `BrowseLibriVoxViewModel` | `searchQuery`, `searchResults`, `syncState`, `activeDownloads`, `featuredBooks`, language/genre/duration filters | `LibriVoxAPIClient`, `LibriVoxCatalogSync` (via SwiftData) |
| `LibriVoxBookDetailViewModel` | `downloadState`, `addToLibraryState`, `isAlreadyInLibrary` | `LibriVoxDownloadService`, `StreamingLibraryService` |
| `StreamedBookDownloadViewModel` | `state` (idle/downloading/done/error) | `LibriVoxDownloadService` |

## Services

Protocol implementations typically `struct`. `LibraryImportService` = concrete `enum` with static methods. Catalog/sync services typically `enum` with static methods (`LibriVoxAPIClient`, `LibriVoxCatalogSync`, `FreeBookCatalogService`). `SamplePlayer` + `NetworkMonitor` = singletons.

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
- `AIEntitlementStore` — StoreKit 2: trial uses tracking + IAP unlock (`AIProductID`). Entitlement state owned entirely by StoreKit (`Transaction.currentEntitlements`); app reads it directly. (RevenueCat observer-mode mirroring removed — `recordPurchase`/`syncPurchases` calls remain commented out for future re-enable.)

### In-App Purchases (two products)

App sells **two IAPs**, both StoreKit-owned. App gates on StoreKit directly — reads `Transaction.currentEntitlements`, no third-party purchase SDK:

| Product | Store ID | Type | Owner store |
|---------|----------|------|-------------|
| AI Features unlock | `andreibaludev.Pageless.ai_unlock` | Non-consumable | `AIEntitlementStore` |
| iCloud Sync | `andreibaludev.Pageless.icloudsync.monthly` | Auto-renewable monthly ($0.99, **no free trial**) | `ICloudSubscriptionStore.shared` |

- **`ICloudSubscriptionStore`** mirrors `AIEntitlementStore`'s shape: `loadProduct()` (`Product.products(for:)`), `refreshEntitlements()` (`Transaction.currentEntitlements`), `purchase()`, `restorePurchases()`, and `Transaction.updates` listener. **Singleton** because `AppDelegate.init` reads `isSubscribedAtLaunch()` (UserDefaults cache) when choosing SwiftData CloudKit database before SwiftUI env objects exist.
- **No free trial.** `introOfferDisplay` returns nil unless App Store product actually carries `.freeTrial` introductory offer, so UI shows "Subscribe" + "$0.99/month" rather than promising trial ASC isn't configured for. Don't reintroduce hardcoded trial string.
- **Reachability (Apple 3.1.1).** iCloud Sync purchase must be reachable in reviewed build: Settings → "iCloud Sync" hero card (shown **unconditionally** in `SettingsView.unlockSection`) → `ICloudSettingsView` → "Subscribe". **Not** hidden behind iCloud sign-in. Prior build rejected under 3.1.1 for shipping subscription product without in-app purchase path.
- **RevenueCat (removed).** RC ran in observer mode purely for dashboard metrics; app never gated on it. To re-enable: re-add `purchases-ios-spm` package, uncomment `// RevenueCat disabled` blocks (Release-only / `if Purchases.isConfigured`-guarded) in `AppDelegate`, `AIEntitlementStore`, `ICloudSubscriptionStore`, then restore RC disclosures in `privacy-policy.md`. Server-side config still exists (project `proj0c83cb7e`, app `app5156e9dfbb`). End-to-end verification needs TestFlight build (local `Products.storekit` receipts can't be validated by RC's backend).
- AI features isolated behind protocols; app works fully without Apple Intelligence
- **iOS 18 deployment-target rule.** Deployment target `18.0` but `FoundationModels` iOS 26-only. Two service types (`MomentNamingService`, `RecapService`) carry `@available(iOS 26, *)`; `MomentAnalysis`/`MomentNamingError`/`RecapError`/`RecapGenerationResult` live in protocol files so iOS-18 callers + mocks use them without availability gating. ViewModel default initializers (`PlayerViewModel`, `AudiobookDetailViewModel`) branch on `if #available(iOS 26, *)` to construct real service vs `Unavailable…` no-op stub. Any new AI-only API must follow same pattern — never reference `FoundationModels` symbols outside `@available`-gated type or `if #available(iOS 26, *)` block.
- **`SystemLanguageModel.default` has ~4096-token budget shared between input + output.** When designing `@Generable` struct, order fields so cheap structured outputs (single-token enums, short arrays) come first, longest prose field last — model generates fields in declaration order, trailing field gets clipped when budget runs out. Post-process any free-text field to handle mid-sentence truncation (see `MomentNamingService.trimToCompleteSentences` / `sanitizedQuoteLine`); never trust model to honor word/sentence-count guides on long tail.

## Feature Systems

### Free Books — two parallel systems

App contains **two independent free-book paths** coexisting by design:

1. **LibriVox catalog (primary, iPhone)** — 20,000+ books from librivox.org. Cached locally in `LibriVoxBook` via `LibriVoxCatalogSync` (24h incremental sync). UI = "Free Books" tab in `ContentView`, driven by `BrowseLibriVoxView` → `LibriVoxBookDetailView`. Supports:
   - **Add to Library (streaming)** via `StreamingLibraryService` — creates `Audiobook` with `isDownloaded == false` + remote URLs on each `AudioTrack`. No files written. Requires network at playback time.
   - **Download** via `LibriVoxDownloadService` — fetches all tracks, creates downloaded `Audiobook` tagged as free book (`isFreeBook = true`, `catalogId = book.id`, each `AudioTrack` keeps its `remoteURLString`) so it shares same iCloud identity as streaming entry, can be matched/re-streamed by id after removal. Also used by `StreamedBookDownloadViewModel` to promote already-added streaming book to downloaded.
   - **Sample preview** via `SamplePlayer` — 20s preview of track without committing.
   - **Network gating** — `NetworkMonitor.shared.isConnected` checked before sample play, sync, streaming.
   - **Covers intentionally not fetched.** LibriVox cover URLs unreliable, so both `LibriVoxDownloadService` + `StreamingLibraryService` always set `coverArtData = nil`, let `GeneratedCoverView` render letter template. Don't reintroduce remote cover fetches here.
   - **Classics-first load order.** `BrowseLibriVoxViewModel.triggerSyncIfNeeded` awaits `performPreload` (curated `curatedClassicIDs` via `LibriVoxAPIClient.fetchBooks(ids:)` → `LibriVoxCatalogSync.seed`) **before** kicking off full `performSync`. Blocking overlay (`isInitialLoading`) only shows while nothing on screen yet; once classics appear, full 20k sync continues behind non-blocking inline banner (`isLoadingFullCatalog`). Don't run full sync ahead of (or concurrently blocking) the preload.
   - **Hardened API client (don't surface raw `DecodingError`).** `LibriVoxAPIClient` never lets "The data couldn't be read because it isn't in the correct format." reach UI. Feed routinely returns `{"error":"…"}` body with HTTP 200 (no match) or HTML page (server hiccup); `fetchData` validates HTTP status (→ `LibriVoxAPIError.serverUnavailable`), lenient `decode` helper maps error-envelope/empty case to `[]` and anything unparseable to `LibriVoxAPIError.unreadableResponse`. `URLError` deliberately **not** wrapped so `isNetworkUnavailable` offline classification still works. `LibriVoxCatalogSync.fetchPageWithRetry` retries transient page failures (3 attempts, linear backoff) so one flaky page can't abort whole sync.
   - **Offline/empty states** (`BrowseLibriVoxView`): `isOfflineWithNoData` / `isOfflineWithCachedData` / `loadFailedWithNoData` all featured-aware (cached classics count as "has data"), driving no-internet state, "Offline — showing saved books" banner, or retriable "Couldn't Load Free Books" state respectively.

2. **Legacy seed catalog (CarPlay)** — `FreeBookCatalogService` exposes 5 hand-picked Internet Archive classics. Downloaded via `FreeBookDownloadService` (background URLSession with published `downloadProgress`, `activeDownloads`, `downloadErrors`). Consumed only by `CarPlayCoordinator` + `LibraryViewModel`. **Do not extend this path for new iPhone features — use the LibriVox path.**

### Reading Activity & Stats

- `ReadingSession` (SwiftData `@Model`) = only persisted row — one chunk = one book × one wall-clock hour bucket, with book's metadata snapshotted so deletion of book doesn't erase history.
- `ReadingSessionRecorder` (`@MainActor`) owned by `AudioPlayerManager`, ticked from its 1-second periodic time observer while `isPlaying`. Continuous play emits chunks every ~5 minutes; pause / track change / book change / app background / finish all flush whatever's accumulated. Chunks shorter than 30s dropped as scrub noise.
- `ReadingStats.compute(sessions:booksFinished:)` = pure aggregate over `[ReadingSession]` → totals, best day/hour/dow, streaks, top author, longest book, free-book share, per-day activity map. No persistence; recomputed when `@Query` of sessions changes.
- Favorites tab pins `ReadingActivityCard` above grid (only when `stats.hasAnyActivity`); tapping pushes `ReadingStatsView` with zoom transition that morphs out of card's heatmap. Full view composes `ReadingStatsSections` (hero, totals, best day, polar best-time-of-day chart, longest book, streaks, metrics, free-books ring) inside `LazyVStack` with `revealOnAppear` + `CountUpText` choreography.
- `ReadingHeatmap` + `HeatmapPalette` (currently `.amber`) = shared visual primitive used by both card + full view.
- `ReadingActivitySeeder` wrapped in `#if DEBUG`, seeds 113 days of synthetic activity for iterating on stats screen without burning real listening time. Don't ship code path calling it from release builds.

### Equalizer (per-book)

- `EqualizerSettings` defines data model: 5 bands (60Hz / 250Hz / 1kHz / 4kHz / 14kHz), presets (flat, voiceBoost, bassBoost, trebleBoost, podcast, custom), preamp 0–12 dB, band gain ±12 dB
- `EqualizerTap` = C-level `MTAudioProcessingTap` running biquad filters + soft limiter on realtime audio thread; coefficients updated under `os_unfair_lock`
- `AudioEqualizerService` (`ObservableObject`) holds live `@Published` state, persists to current `Audiobook.equalizerConfiguration`, builds `AVAudioMix` injected into each `AVPlayerItem`
- `EqualizerSheet` = user-facing UI; reads/writes via `@EnvironmentObject AudioEqualizerService`

### Onboarding

**Standalone welcome flow** shown once on first launch (and on demand via Settings → "Reset Onboarding"). Replaced old phase-based spotlight walkthrough — no longer any `OnboardingStep` / `SpotlightOverlayView` / `.spotlightTarget()` machinery; don't reintroduce.

- **`OnboardingManager`** — now just completion gate: `isComplete` (persisted to `onboardingComplete`), `complete()`, `reset()`. Init migrates legacy users — anyone with old `onboardingPhase == 3` (completed) treated as complete so they don't re-see onboarding. `ContentView` presents `OnboardingFlowView` via `.fullScreenCover` while `!isComplete`.
- **`OnboardingFlowView`** (host) — paged vertical `ScrollView` (`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`) of six full-screen scenes with floating right-edge progress-dot rail. Active scene index drives each scene's reveal/count-up/stagger animations (triggering on `.onAppear` wrong here — paged rows instantiate before they center).
- **Preference controls bind live to app's existing `@AppStorage` keys** (`resumeBacktrackSeconds`, `skipBackSeconds`, `skipForwardSeconds`, `momentBacktrackSeconds`) — so persistence automatic, scene-6 summary shares one source of truth, choice freely reversible. "Open Library" calls `onboarding.complete()`, routes into chosen home tab (free → Free Books, own → All Books). **"Free books" choice persists** via `@AppStorage("startOnFreeBooks")`: when true, app launches on Free Books on **every** launch (one-time `.onAppear` guard in `ContentView` applies it for relaunched users) **and** reorders library tabs to Favorites / Free Books / All Books in both `tabPicker` + swipeable `libraryContent` (driven by `tabOrder` computed property). Choosing "My books" (and all legacy users) leaves `startOnFreeBooks=false` — unchanged: lands on Favorites, tab order Favorites / All Books / Free Books.
- **Scenes 4 (Apple Intelligence) and 5 (iCloud Sync) informational only** — no paywall, no toggles. Don't wire purchase/sync state into them.
- **`OnboardingScenes`** holds six scenes + widgets (choice cards, drag `OBRulerPicker`, chip rows, stepper, `OBHeatmap`, moment-naming card, `OBSyncGraphic`, summary). **`OnboardingTheme`** holds design tokens (`OB.*` colors, `OBMotion`), type primitives (`OBEyebrow`/`OBHeadline`/`OBSub`/`obSerif`), `obReveal` / `obParallax` modifiers.
- **Requirement: identical on every device/iOS version.** Fixed point sizes throughout, fixed 402pt content column centered on wider screens, `.dynamicTypeSize(.large)` clamp at root (never Dynamic Type), app's own light/dark theme via `preferredColorScheme(forceDarkMode ? .dark : nil)`. All animations honor Reduce Motion.

### iCloud Sync

Library metadata, progress, moments, EQ configuration, reading sessions sync across devices via CloudKit private database. Audio files not synced — must be re-acquired on each device. **iCloud Sync = paid feature** — auto-renewable monthly subscription ($0.99, no trial); see "In-App Purchases" above.

- **`IcloudSyncGate`** — single decision point: requires active subscription (`ICloudSubscriptionStore.isSubscribedAtLaunch()`) AND `iCloudSyncEnabled` UserDefaults toggle AND `FileManager.ubiquityIdentityToken`. When any false, `AppDelegate` builds SwiftData container with `.none` database. Container ID: `iCloud.andreibaludev.Pageless`.
- **Split `ModelContainer`** — `AppDelegate` creates two configurations: `"synced"` (Audiobook/AudioTrack/Moment/ReadingSession → CloudKit private DB when enabled) and `"local"` (LibriVoxBook → never synced).
- **Orphan detection** — `OrphanDetectionService` runs at launch and after every `NSPersistentCloudKitContainer.eventChangedNotification` import event. Any book marked `isDownloaded = true` whose storage folder absent gets flipped to `isDownloaded = false`, making it recoverable orphan.
- **Fingerprinting** — `LibraryImportService` computes SHA-256 content fingerprint (truncated to 16 bytes of audio data) for each imported track, stored on `AudioTrack.contentFingerprint`. `FingerprintBackfillService` backfills existing tracks on first launch after upgrade.
- **Restore on re-import (own books)** — when user imports files on new device, `LibraryViewModel` calls `OrphanRestoreService.findMatch` to fingerprint-compare against orphan candidates. Match triggers `RestoreMatchSheet` ("Restore from iCloud" / "Add as new"). `OrphanRestoreService.adopt` rewrites orphan's `AudioTrack` records in-place, preserving all moments/progress/EQ.
- **Match by id (free books)** — free books carry no file fingerprint, so match on `catalogId` instead. Removing free book with sync on calls `LibraryImportService.archiveFreeBook` (drops files, sets `isArchived = true`, keeps synced record + remote URLs). Re-adding same book from Free Books tab — streaming **or** downloading — calls `OrphanRestoreService.fetchFreeBackup(catalogId:)`; hit raises confirmation in `LibriVoxBookDetailView` ("Import from iCloud" reuses/re-downloads backup in place, "Add as New" creates fresh copy). If user added as new, `AudiobookDetailView`'s iCloud button restores later via `OrphanRestoreService.restoreFreeBackup` (cloud-wins, no files to copy). `isArchived` = free-book analogue of own book's `!isDownloaded` orphan state — needed because free `!isDownloaded` alone ambiguous (active streaming vs removed).
- **`CloudLibraryView`** — full iCloud Library, not just orphans: every book user ever added always listed so backup visibly verifiable. Reachable two ways: Settings → iCloud Library, **and** dedicated iCloud button in main library header shown only when `ICloudSubscriptionStore.isSubscribedAtLaunch()` (replaced old header sort button — sort moved to per-tab chevron menus). Four mutually-exclusive buckets — **On this iPhone** (`isDownloaded && !isArchived`, own + free), **Streaming** (`!isDownloaded && isFreeBook && !isArchived`, status-only), **In iCloud only** (`!isDownloaded && !isFreeBook`, "Locate…" picker), **Removed free books** (`isArchived && isFreeBook`, "Stream"). Swipe-to-delete on own rows = **only** permanent cloud-delete path.
- **`ICloudBackupBadge` (sync assurance)** — subtle "Backed up to iCloud" affordance shown on each book (cover overlay + detail inline) whenever `IcloudSyncGate.isEnabled()`. NSPersistentCloudKitContainer exposes no per-object "synced" flag, so this = honest *static* badge (sync on ⇒ every synced-store record backed up), not real-time pulse — gated on subscription+toggle so it never promises backup to non-subscribers.
- **Delete copy subscription-aware** — `ContentView`'s delete dialog branches all six paths (streaming-only / downloaded-free / own × sync-on/off) on `IcloudSyncGate.isEnabled()`. Subscriber own-book delete = single non-destructive **"Remove from this iPhone"** (soft-delete: drops local audio, keeps iCloud backup); intentionally no second local option (a "files-on-disk-but-not-in-library" state has no sensible meaning). Non-subscribers keep two-option hard delete ("Remove from App" / "Also Delete Files").
- **`isStreamingOnly` tiebreaker** — `Audiobook.isStreamingOnly` excludes own-book orphans (`!isDownloaded && !isFreeBook`) so they appear in Cloud Library, not treated as streaming books.

### CarPlay
- `CarPlaySceneDelegate` — connects CarPlay scene to `CarPlayCoordinator`
- `CarPlayCoordinator` — full CarPlay UI templates, now-playing, moment saving, browsing legacy seed catalog
- `CarPlayVoiceSearch` — hands-free dictation over Speech framework, auto-stops on silence
- `VoiceSearchPermissions` — primes mic + speech permissions on iPhone at app launch (`PagelessApp.task`) so CarPlay never has to surface permission prompt mid-drive (it can't)
- `AppDelegate` — background URL session handler + CarPlay scene registration

### Siri / App Intents
- `AudiobookIntents.swift` — `PlayLatestBookIntent` exposed via `UnpagedAppShortcuts: AppShortcutsProvider` ("Play Latest Book"). Triggered shortcut writes UserDefaults flag, `PagelessApp` consumes it on `scenePhase == .active`.

## Settings & Preferences

`@AppStorage` keys typed via enums in `PlaybackSettings.swift`:
- `LibrarySortOption` — recent, title, author, duration, dateAdded
- `ResumeBacktrackOption`, `SkipIntervalOption`, `MomentBacktrackOption`, `SleepTimerOption`

All enums `CaseIterable, Identifiable`.

## Key Patterns

- **MVVM**: Views own `@Query`, `@AppStorage`, UI state. ViewModels own business state + async workflows. Services stateless + injectable (exceptions: `AudioPlayerManager`, `AudioEqualizerService`, `SamplePlayer`, `NetworkMonitor`).
- **Dependency injection**: Initializer injection on ViewModels with protocol-typed services; default implementations provided so views call `ViewModel()` without arguments.
- **SwiftData queries**: Use `@Query` in views; pass `modelContext` explicitly to ViewModels/services.
- **Security-scoped file access**: For user-imported files, always pair `startAccessingSecurityScopedResource` with release path (see `LibraryViewModel.releaseSecurityScopedAccess()`).
- **Async bridging**: Use `withCheckedContinuation` / `withCheckedThrowingContinuation` when bridging completion-handler APIs (Speech framework).
- **AI isolation**: `AppleIntelligenceCapability` guards UI visibility; ViewModels catch service errors + fall back gracefully. On iOS 18 helper hard-returns `.unsupportedDevice` / `false` so AI surfaces never render.
- **Schema migration**: Private backing field pattern (`_fieldName`) with computed getter/setter for post-launch columns; new fields nullable on disk.
- **Streaming vs downloaded**: Treat `Audiobook.isStreamingOnly` as load-bearing — anything touching on-disk path must check it. Promotion to downloaded goes through `LibriVoxDownloadService`.
- **Cover fallback**: Any view displaying cover art must fall through to `GeneratedCoverView(title:)` when `coverArtData == nil` — not gradient + SF Symbol. `NowPlayingUpdater` mirrors this for lock screen / CarPlay artwork via `GeneratedCoverView.renderImage(title:side:)` with `[title: UIImage]` cache so it doesn't re-render every periodic tick.
- **CarPlay permission constraint**: Mic + speech permission prompts cannot appear on CarPlay screen, so `VoiceSearchPermissions.primeIfNeeded()` runs at iPhone launch. Don't add new permission requests that can fire only on CarPlay.
- **Now-Playing metadata convention** (`NowPlayingUpdater.update`): track title → `MPMediaItemPropertyTitle` (use `track.displayTitle`, not raw `track.title` — see Title display below), book title → `MPMediaItemPropertyAlbumTitle` (do NOT concatenate author into this), author → `MPMediaItemPropertyArtist`. Always set `MPNowPlayingInfoCenter.default().playbackState` after writing `nowPlayingInfo` — Siri uses it to route pause/resume intents.
- **Title display / rename propagation**: Every playback surface (`PlayerView` big title, `NowPlayingUpdater` lock screen + CarPlay now-playing) reads `AudioTrack.displayTitle`, NOT `track.title`. Single-track books: `displayTitle` falls back to renamable `Audiobook.title` — lone track title usually file-metadata noise ("Chapter 1") no rename touches (`commitRename` writes only `audiobook.title`). Multi-track keeps per-chapter `title`. `MiniPlayerBar` shows book title primary line, drops duplicate single-track chapter line via `miniSecondaryLine`. Make rename universal via display-side fallback — do NOT mutate `AudioTrack.title` rows on rename (no migration, fixes existing books instantly). CarPlay chapter-list rows still show raw per-track `title`.

## Testing

Tests use Swift Testing framework (`import Testing`). To run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]` (no `*_sim` variant — see Build & Run).

Mock implementations live in `PagelessTests/Mocks/`:
- `MockTranscriptionService`, `MockMomentAnalyzer`, `MockRecapService`, `MockAudioExtractor`, `MockFreeBookDownloadService`

All protocol-backed services have corresponding mocks for ViewModel tests. New LibriVox-path code currently exercised through integration-style tests against SwiftData in-memory containers rather than via mocks — if you add new protocol there, add matching mock under `PagelessTests/Mocks/`.

**In-memory test containers**: always pass `cloudKitDatabase: .none` to `ModelConfiguration`. Default = `.automatic`, which on device picks up host app's CloudKit entitlement + triggers CloudKit-shape validation that fails even with everything defaulted — test bundle's view of schema differs from production. `SchemaCompatibilityTests.syncedSchemaSatisfiesCloudKitConstraints` = one place that intentionally exercises `.private(...)` validation, via file-backed temp store.

**Hold container in a local**: `let container = try makeContainer(); let context = container.mainContext` — never `try makeContainer().mainContext`. Container released immediately + mainContext crashes host app at first fetch.