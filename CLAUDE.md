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

The repo ships two markdown files that are hosted publicly (currently via GitHub Gist) and linked from the App Store listing:

- `support.md` — Support URL contents (FAQ, troubleshooting, contact)
- `privacy-policy.md` — Privacy Policy URL contents

**Keep these in sync with the app.** Whenever a change touches any of the following, update the relevant file(s) in the same commit:

- Permissions requested (`Info.plist` `NS*UsageDescription` keys) → both files
- Network behavior, third-party services, or data collected → `privacy-policy.md`
- AI features, IAP terms, trial mechanics → both files
- Supported devices, minimum iOS version (`IPHONEOS_DEPLOYMENT_TARGET`, `TARGETED_DEVICE_FAMILY`) → `support.md`
- New user-visible features that warrant a FAQ entry → `support.md`
- Contact email or developer name → both files

After editing, remind the user to push the new content to their public Gist(s) — the repo files are the source of truth, but the App Store points to the Gist URLs.

## Build & Run

Use XcodeBuildMCP tools for all build/run operations:

- **Build & run on simulator**: `mcp__XcodeBuildMCP__build_run_sim` (scheme: `Pageless`)
- **Build only**: `mcp__XcodeBuildMCP__build_sim`
- **Run tests**: `mcp__XcodeBuildMCP__test_sim`
- **Clean**: `mcp__XcodeBuildMCP__clean`

Always call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/simulator settings before building.

**Device target**: Always build and run on **Andrei's iPhone 15 Pro** — identifier `00008130-000471A80C81001C` (UDID `BAE98D59-834B-5B20-8E9A-8943DCE6F7FD`). Use `mcp__XcodeBuildMCP__build_run_device` / `mcp__XcodeBuildMCP__build_device` instead of simulator tools. Use the `xcode-device-build` skill if needed for device setup. Apple Intelligence (`FoundationModels`) only runs on 15 Pro / 16+ hardware, so the simulator can't exercise AI surfaces.

External packages: **RevenueCat** (`purchases-ios-spm`) for purchase analytics in observer mode. All other code uses native Apple frameworks only (AVFoundation, MediaToolbox, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, Intents, CarPlay, Network).

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

```
Pageless/
├── App/
│   ├── PagelessApp.swift          @main; ModelContainer, scene wiring, env injection, voice-permission priming, Siri shortcut handoff
│   ├── AppDelegate.swift          Owns split ModelContainer (synced+local configs), AudioPlayerManager, FreeBookDownloadService; background URLSession handler; CarPlay scene config; observes NSPersistentCloudKitContainer.eventChangedNotification to re-run orphan detection after CloudKit import batches
│   └── CarPlaySceneDelegate.swift CarPlay interface controller connector
├── AppIntents/
│   └── AudiobookIntents.swift     `PlayLatestBookIntent` + `UnpagedAppShortcuts` provider ("Play Latest Book")
├── Configuration/
│   └── AIProductID.swift          StoreKit product ID constant for AI unlock
├── Models/
│   ├── Audiobook.swift            SwiftData @Model; playback, progress marker, recap, EQ, streaming-vs-downloaded, free-book metadata
│   ├── AudioTrack.swift           SwiftData @Model; per-track metadata (supports remote URLs for streaming); `contentFingerprint` (SHA-256 hex) for iCloud orphan matching
│   ├── Moment.swift               SwiftData @Model; bookmarks with AI metadata
│   ├── MomentEnums.swift          `MomentCategory` (10 types), `MomentMood` (8 types)
│   ├── PlaybackSettings.swift     `LibrarySortOption`, `SkipIntervalOption`, `ResumeBacktrackOption`, `MomentBacktrackOption`, `SleepTimerOption`
│   ├── EqualizerSettings.swift    `EqualizerBand`, `EqualizerPreset` (flat/voiceBoost/bassBoost/trebleBoost/podcast/custom), `EqualizerConfiguration`
│   ├── LibriVoxBook.swift         SwiftData @Model for the cached LibriVox catalog (20k+ rows)
│   ├── CachedLibriVoxTrack.swift  Lightweight non-persisted track snapshot embedded JSON-encoded inside `LibriVoxBook.cachedTracks`
│   ├── ReadingSession.swift       SwiftData @Model; per-chunk listening row (book snapshot + hour bucket + minutes) feeding the Reading Activity heatmap
│   ├── ReadingStats.swift         Non-persisted `ReadingStats` aggregate (`compute(sessions:booksFinished:)`) + `ReadingDayActivity` per-day rollup
│   └── FreeBookCatalogEntry.swift Legacy non-persisted struct for the 5-seed CarPlay free-book catalog
├── ViewModels/
│   ├── PlayerViewModel.swift                Moment creation, AI naming workflow, smart save warning
│   ├── AudiobookDetailViewModel.swift       Moment filtering, recap generation
│   ├── LibraryViewModel.swift               Import workflow, delete/rename, legacy free-book downloads (CarPlay/seed catalog)
│   ├── BrowseLibriVoxViewModel.swift        Catalog sync, search, filters (language/genre/duration), featured books, downloads-in-progress tracking
│   ├── LibriVoxBookDetailViewModel.swift    Per-book "Download" and "Add to Library (streaming)" state machines
│   └── StreamedBookDownloadViewModel.swift  Promotes a streaming-only `Audiobook` to a fully downloaded one
├── Views/
│   ├── ContentView.swift          Root tabs (Favorites / All Books / Free Books), sort, mini player, sheet routing
│   ├── PlayerView.swift           Full-screen player with controls, moment saving, EQ entry
│   ├── AudiobookDetailView.swift  Tracks, moments grid, recap, cover editing
│   ├── AudiobookCardView.swift    Library grid cell
│   ├── AudiobookTrackRow.swift    Track list item
│   ├── MiniPlayerBar.swift        Persistent bottom playback bar
│   ├── MomentRow.swift            Moment list item with play/edit
│   ├── MomentEditSheet.swift      Modal for naming moments + AI-generated metadata display
│   ├── MomentFilterSheet.swift    Category/character/mood filtering UI
│   ├── ImportAudiobookSheet.swift Import workflow with file preview
│   ├── SettingsView.swift         Playback preferences + iCloud Sync section (toggle + Cloud Library link)
│   ├── AISettingsView.swift       AI feature toggles, trial management, IAP unlock
│   ├── CoverCropView.swift        Image cropping interface for cover art
│   ├── CloudLibraryView.swift     iCloud orphan recovery: own-book "Locate…" file picker + free-book one-tap stream restore
│   ├── RestoreMatchSheet.swift    Shown on import when fingerprint matches a synced orphan; prompts "Restore from iCloud" vs "Add as new"
│   ├── GeneratedCoverView.swift   Deterministic letter-template cover used as universal fallback when `coverArtData == nil`; also renders to UIImage for MPNowPlayingInfoCenter / CarPlay artwork
│   ├── EqualizerSheet.swift       5-band EQ + preamp + presets UI; mounted from player
│   ├── FreeBooks/
│   │   ├── BrowseLibriVoxView.swift       Search + filters + featured + active downloads
│   │   ├── LibriVoxBookDetailView.swift   Cover/metadata, sample preview, download/add-to-library
│   │   └── LibriVoxBookRow.swift          Search result row with inline sample button
│   ├── ReadingStats/
│   │   ├── ReadingActivityCard.swift     Compact heatmap card pinned at the top of the Favorites tab; tap pushes the full screen
│   │   ├── ReadingStatsView.swift        Full-screen stats view (zoom-transitions out of the card)
│   │   ├── ReadingStatsSections.swift    Hero, totals, best day, polar best-time-of-day chart, longest book, streaks, metrics, free-books ring
│   │   └── ReadingHeatmap.swift          Reusable heatmap renderer + `HeatmapPalette` (uses `.amber` by default)
│   └── Onboarding/
│       ├── OnboardingStep.swift          Enum defining 7 onboarding phases
│       └── SpotlightOverlayView.swift    Spotlight tutorial overlay
├── Services/
│   ├── Protocols/
│   │   ├── TranscriptionProviding.swift
│   │   ├── MomentAnalyzing.swift              (also defines `MomentAnalysis`, `MomentNamingError`, and `UnavailableMomentAnalyzer` fallback for iOS < 26)
│   │   ├── AudioExtracting.swift
│   │   ├── RecapProviding.swift               (also defines `RecapGenerationResult`, `RecapError`, and `UnavailableRecapProvider` fallback for iOS < 26)
│   │   └── FreeBookDownloading.swift          (legacy seed-catalog download protocol)
│   ├── AudioPlayerManager.swift            Central playback state (ObservableObject); owns `equalizer: AudioEqualizerService`
│   ├── PlaybackPersistence.swift           Progress tracking, high-water mark, SwiftData saves
│   ├── NowPlayingUpdater.swift             MPRemoteCommandCenter + MPNowPlayingInfoCenter
│   ├── LibraryImportService.swift          User-file import with security-scoped access (enum + static methods)
│   ├── TranscriptionService.swift          Speech framework wrapper
│   ├── MomentNamingService.swift           FoundationModels AI moment analysis — `@available(iOS 26, *)`
│   ├── RecapService.swift                  FoundationModels progress recap generation — `@available(iOS 26, *)`
│   ├── ReadingSessionRecorder.swift        Accumulates wall-clock playback time and flushes `ReadingSession` rows (5-min chunks, lifecycle boundaries)
│   ├── ReadingActivitySeeder.swift         DEBUG-only synthetic-activity seeder (113 days) for stats screen iteration
│   ├── AudioExtractionService.swift        AVAssetExportSession audio segment extraction (50s segments)
│   ├── AudioEqualizerService.swift         Live 5-band EQ + preamp orchestration; builds AVAudioMix; @Published bindings to UI
│   ├── EqualizerTap.swift                  C-level MTAudioProcessingTap: biquad filters + soft limiter (realtime audio thread)
│   ├── FreeBookCatalogService.swift        Legacy 5-seed catalog (Internet Archive) — still used by CarPlay
│   ├── FreeBookDownloadService.swift       Legacy background URLSession seed-catalog downloader — used by CarPlay
│   ├── LibriVoxAPIClient.swift             HTTP client for librivox.org (catalog pages, incremental sync, track lists)
│   ├── LibriVoxCatalogSync.swift           Incremental + full sync into SwiftData (`LibriVoxBook`); 24h cadence
│   ├── LibriVoxDownloadService.swift       Downloads LibriVox tracks → creates local `Audiobook`; also promotes streaming → downloaded
│   ├── StreamingLibraryService.swift       Adds a streaming-only `Audiobook` (no files; remote URLs persisted on `AudioTrack`)
│   ├── SamplePlayer.swift                  Singleton 20-second track preview (one book at a time)
│   ├── NetworkMonitor.swift                Network framework reachability; `shared.isConnected`
│   ├── OnboardingManager.swift             Multi-phase onboarding state (UserDefaults)
│   ├── CarPlayCoordinator.swift            CarPlay UI templates, now-playing, moment saving, legacy free-book browsing
│   ├── CarPlayVoiceSearch.swift            Hands-free dictation: mic → Speech framework with silence auto-stop
│   ├── VoiceSearchPermissions.swift        Centralised mic + speech permission gating (primed at app launch)
│   ├── AudiobookSavedProgressResume.swift  Resume-from-bookmark logic (enum)
│   ├── AppleIntelligenceCapability.swift   Runtime AI feature detection; iOS-18-safe (internal `#available(iOS 26, *)` branches, returns `.unsupportedDevice` below iOS 26)
│   ├── AIEntitlementStore.swift            StoreKit 2 IAP + trial-use tracking
│   ├── IcloudSyncGate.swift                Opt-in iCloud sync gate: reads `iCloudSyncEnabled` UserDefaults toggle + ubiquity identity check; holds CloudKit container ID
│   ├── FingerprintBackfillService.swift    One-shot background pass to SHA-256-fingerprint pre-existing tracks for orphan matching after upgrade
│   ├── OrphanDetectionService.swift        At launch (and after each CloudKit import batch), flips `isDownloaded=false` for books whose storage folder is absent on this device
│   └── OrphanRestoreService.swift          Fingerprint-matches a pending import to a synced orphan and rewrites its `AudioTrack` records in-place, preserving moments/progress/EQ
└── Utilities/
    ├── TimeFormatter.swift                 Clock string formatting, duration summaries
    ├── BookDescriptionFormatting.swift     HTML fragment → plain text (entity decoding, block breaks)
    └── Color+Theme.swift                   Cream/cardWhite theme with dark mode

PagelessTests/
├── Mocks/
│   ├── MockTranscriptionService.swift
│   ├── MockMomentAnalyzer.swift
│   ├── MockRecapService.swift
│   ├── MockAudioExtractor.swift
│   └── MockFreeBookDownloadService.swift
├── ModelTests/
│   ├── AudiobookTests.swift
│   ├── AudiobookAdditionalTests.swift
│   ├── AudiobookEqualizerTests.swift
│   ├── AudiobookFreeBookTests.swift
│   ├── AudioTrackTests.swift
│   ├── EqualizerSettingsTests.swift
│   ├── FreeBookCatalogEntryTests.swift
│   └── MomentTests.swift
├── ModelTests/
│   └── SchemaCompatibilityTests.swift   CloudKit schema constraint checks (no `.unique` on synced models, explicit inverses)
├── ServiceTests/
│   ├── AudioEqualizerServiceTests.swift
│   ├── AudioPlayerManagerSkipTests.swift
│   ├── AudioSessionInterruptionTests.swift
│   ├── AudiobookSavedProgressResumeTests.swift
│   ├── FreeBookCatalogServiceTests.swift
│   ├── FreeBookDownloadServiceTests.swift
│   ├── LibraryImportFingerprintTests.swift  SHA-256 fingerprint generation + backfill logic
│   ├── MomentNamingServiceLogicTests.swift
│   ├── NowPlayingUpdaterTests.swift
│   ├── OnboardingManagerTests.swift
│   ├── OrphanRestoreServiceTests.swift      Orphan adopt / fingerprint matching
│   ├── PlaybackPersistenceTests.swift
│   ├── RecapServiceLogicTests.swift
│   └── SiriIntentTests.swift
├── ServicesTests/
│   └── PlaybackPersistenceRecapTests.swift
└── ViewModelTests/
    ├── AudiobookDetailViewModelFilterTests.swift
    ├── AudiobookDetailViewModelTests.swift
    ├── LibraryViewModelFreeBookTests.swift
    ├── LibraryViewModelTests.swift
    ├── PlayerViewModelCommitTests.swift
    └── PlayerViewModelTests.swift

PagelessUITests/
├── PagelessUITests.swift
└── PagelessUITestsLaunchTests.swift
```

## Data Layer (SwiftData)

**Five models** registered in the `ModelContainer` (see `AppDelegate.swift`): `Audiobook`, `AudioTrack`, `Moment`, `LibriVoxBook`, `ReadingSession`.

Audio files for downloaded books are stored at `Application Support/Audiobooks/[UUID]/`. Cover images use SwiftData external storage. Streaming-only books store remote URLs on `AudioTrack` and have `Audiobook.isDownloaded == false`.

```
Audiobook (@Model final)
├── id: UUID, title, author, folderName, coverArtData (external storage), createdAt, lastPlayedAt
├── Playback state: currentTrackIndex, currentTime, playbackRate, isFinished, totalDuration
├── Progress marker: progressTrackIndex?, progressTime?, progressUpdatedAt?
├── Progress recap: progressRecapText?, progressRecapHeadline?, progressRecapAnchorTrackIndex?, progressRecapAnchorTime?
├── Free-book metadata: isFavorite, isFreeBook, catalogId?, isDownloaded (false ⇒ streaming-only)
├── Equalizer state (per-book): equalizerConfiguration → {isEnabled, preset, preampDB, bandGainsDB[5]} (JSON-backed)
├── Computed: listenedDuration, progress, remainingDuration, currentTrackTitle, displayAuthor, castList, isStreamingOnly
├── Recap helpers: clearProgressRecap(), storeProgressRecap(...), discardProgressRecapIfAnchorMismatched()
└── @Relationship: tracks[] + moments[] (both cascade delete)

AudioTrack (@Model final)
└── id, title, originalFileName, storedFileName, orderIndex, duration, contentFingerprint? (SHA-256 hex, used for iCloud orphan matching), audiobook?

Moment (@Model final)
├── id, trackIndex, time, createdAt
├── label, transcript?, aiGeneratedName, notes, isPinned
├── AI fields (JSON-serialized): categories[], quoteLine?, characters[], mood?
└── audiobook?

LibriVoxBook (@Model final)
├── id (unique), title, authorDisplay, bookDescription, language, totalTimeSecs
├── genres (JSON-backed), cachedTracks (JSON-backed [CachedLibriVoxTrack]), cover URLs, RSS URL
└── Computed: formattedDuration, estimatedDownloadSizeMB, bestCoverURL

ReadingSession (@Model final)
├── id (unique), date (start-of-day), dayKey ("YYYY-MM-DD"), hour (0...23), minutes (≥1)
├── Book snapshot (so stats survive book deletion): bookID, bookTitle, bookAuthor, isFreeBook
└── createdAt
```

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
- `AIEntitlementStore` — StoreKit 2: trial uses tracking + IAP unlock (`AIProductID`). Entitlement state is owned by StoreKit (`Transaction.currentEntitlements`); RevenueCat runs in observer mode (`purchasesAreCompletedBy: .myApp`, SK2) purely for dashboard metrics. After each verified SK2 transaction, `AIEntitlementStore` calls `Purchases.shared.recordPurchase(_:)` / `syncPurchases()` so RC sees the event. `Purchases.configure(...)` runs **only in Release builds** (`#if !DEBUG` in `AppDelegate`) because Xcode's local `Products.storekit` configuration produces simulated receipts that RC's backend cannot validate. DEBUG runs do not initialize RC at all; per-purchase calls are guarded by `if Purchases.isConfigured`. End-to-end RC verification therefore requires a TestFlight build with a Sandbox tester signed in.
- AI features are isolated behind protocols; app works fully without Apple Intelligence
- **iOS 18 deployment-target rule.** The deployment target is `18.0` but `FoundationModels` is iOS 26-only. The two service types (`MomentNamingService`, `RecapService`) carry `@available(iOS 26, *)`; `MomentAnalysis`/`MomentNamingError`/`RecapError`/`RecapGenerationResult` live in the protocol files so iOS-18 callers and mocks can use them without availability gating. ViewModel default initializers (`PlayerViewModel`, `AudiobookDetailViewModel`) branch on `if #available(iOS 26, *)` to construct the real service vs. the `Unavailable…` no-op stub. Any new AI-only API must follow the same pattern — never reference `FoundationModels` symbols outside an `@available`-gated type or an `if #available(iOS 26, *)` block.
- **`SystemLanguageModel.default` has a ~4096-token budget shared between input and output.** When designing a `@Generable` struct, order fields so cheap structured outputs (single-token enums, short arrays) come first and the longest prose field is last — the model generates fields in declaration order and the trailing field is what gets clipped when the budget runs out. Post-process any free-text field to handle mid-sentence truncation (see `MomentNamingService.trimToCompleteSentences` / `sanitizedQuoteLine`); never trust the model to honor word/sentence-count guides on the long tail.

## Feature Systems

### Free Books — two parallel systems

The app contains **two independent free-book paths** that coexist by design:

1. **LibriVox catalog (primary, iPhone)** — 20,000+ books from librivox.org. Cached locally in `LibriVoxBook` via `LibriVoxCatalogSync` (24h incremental sync). UI is the "Free Books" tab in `ContentView`, driven by `BrowseLibriVoxView` → `LibriVoxBookDetailView`. Supports:
   - **Add to Library (streaming)** via `StreamingLibraryService` — creates an `Audiobook` with `isDownloaded == false` and remote URLs on each `AudioTrack`. No files written. Requires network at playback time.
   - **Download** via `LibriVoxDownloadService` — fetches all tracks, creates a normal local `Audiobook`. Also used by `StreamedBookDownloadViewModel` to promote an already-added streaming book to downloaded.
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
- `OnboardingManager` — 4 phases: `phase1`, `waitingForBook`, `phase2`, `completed` (UserDefaults persistence)
- `OnboardingStep` — 7 steps: `p1AddButton`, `p1Settings`, `p1AILink`, `p1AIPage`, `p1DeviceCapability`, `p2Progress`, `p2Moments`
- `SpotlightOverlayView` — spotlight tutorial overlay rendered over content

### iCloud Sync

Library metadata, progress, moments, EQ configuration, and reading sessions sync across devices via CloudKit private database. Audio files are not synced — they must be re-acquired on each device.

- **`IcloudSyncGate`** — single decision point: reads the `iCloudSyncEnabled` UserDefaults toggle AND checks `FileManager.ubiquityIdentityToken`. When disabled, `AppDelegate` builds the SwiftData container with `.none` database. Container ID: `iCloud.andreibaludev.Pageless`.
- **Split `ModelContainer`** — `AppDelegate` creates two configurations: `"synced"` (Audiobook/AudioTrack/Moment/ReadingSession → CloudKit private DB when enabled) and `"local"` (LibriVoxBook → never synced).
- **Orphan detection** — `OrphanDetectionService` runs at launch and after every `NSPersistentCloudKitContainer.eventChangedNotification` import event. Any book marked `isDownloaded = true` whose storage folder is absent gets flipped to `isDownloaded = false`, making it a recoverable orphan.
- **Fingerprinting** — `LibraryImportService` computes a SHA-256 content fingerprint (truncated to 16 bytes of audio data) for each imported track, stored on `AudioTrack.contentFingerprint`. `FingerprintBackfillService` backfills existing tracks on first launch after upgrade.
- **Restore on re-import** — when a user imports files on a new device, `LibraryViewModel` calls `OrphanRestoreService.findMatch` to fingerprint-compare against orphan candidates. A match triggers `RestoreMatchSheet` ("Restore from iCloud" / "Add as new"). `OrphanRestoreService.adopt` rewrites the orphan's `AudioTrack` records in-place, preserving all moments/progress/EQ.
- **`CloudLibraryView`** — manual recovery screen (Settings → Cloud Library). Own-book orphans get a "Locate…" file picker; free-book orphans get a "Stream" button that re-enables streaming.
- **`isStreamingOnly` tiebreaker** — `Audiobook.isStreamingOnly` excludes own-book orphans (`!isDownloaded && !isFreeBook`) so they appear in Cloud Library, not treated as streaming books.

### CarPlay
- `CarPlaySceneDelegate` — connects CarPlay scene to `CarPlayCoordinator`
- `CarPlayCoordinator` — full CarPlay UI templates, now-playing, moment saving, browsing the legacy seed catalog
- `CarPlayVoiceSearch` — hands-free dictation over the Speech framework, auto-stops on silence
- `VoiceSearchPermissions` — primes mic + speech permissions on iPhone at app launch (`PagelessApp.task`) so CarPlay never has to surface a permission prompt mid-drive (it can't)
- `AppDelegate` — background URL session handler + CarPlay scene registration

### Siri / App Intents
- `AudiobookIntents.swift` — `PlayLatestBookIntent` exposed via `UnpagedAppShortcuts: AppShortcutsProvider` ("Play Latest Book"). Triggered shortcut writes a UserDefaults flag and `PagelessApp` consumes it on `scenePhase == .active`.

## View Hierarchy

```
PagelessApp (@main)
└── WindowGroup → ContentView (LibraryViewModel)
    ├── EnvironmentObjects: AudioPlayerManager, AudioEqualizerService, AIEntitlementStore
    ├── Environment: OnboardingManager, FreeBookDownloadService
    ├── NavigationStack
    │   ├── libraryHeader (sort options)
    │   ├── tabPicker (Favorites / All Books / Free Books)
    │   ├── (Favorites tab only) ReadingActivityCard → NavigationLink → ReadingStatsView (zoom transition)
    │   └── booksGrid OR BrowseLibriVoxView
    │       ├── (library tabs) LazyVGrid → AudiobookCardView[] → AudiobookDetailView (AudiobookDetailViewModel)
    │       │   ├── resumeAnchorRow (play from progress or recap)
    │       │   ├── MomentRow[] → MomentEditSheet
    │       │   ├── MomentFilterSheet
    │       │   └── AudiobookTrackRow[]
    │       └── (free-books tab) BrowseLibriVoxView (BrowseLibriVoxViewModel)
    │           ├── LibriVoxBookRow[] (with inline SamplePlayer button)
    │           └── LibriVoxBookDetailView (LibriVoxBookDetailViewModel)
    ├── MiniPlayerBar (when currentAudiobook != nil)
    ├── PlayerView (.sheet, full-screen) → PlayerViewModel
    │   ├── MomentEditSheet (.sheet)
    │   └── EqualizerSheet (.sheet)
    ├── ImportAudiobookSheet (.sheet)
    ├── SettingsView (.sheet)
    └── AISettingsView (.sheet)
```

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

## Testing

Tests use Swift Testing framework (`import Testing`). To run: use `mcp__XcodeBuildMCP__test_sim` or `xcodebuild test`.

Mock implementations live in `PagelessTests/Mocks/`:
- `MockTranscriptionService`, `MockMomentAnalyzer`, `MockRecapService`, `MockAudioExtractor`, `MockFreeBookDownloadService`

All protocol-backed services have corresponding mocks for ViewModel tests. New LibriVox-path code is currently exercised through integration-style tests against SwiftData in-memory containers rather than via mocks — if you add a new protocol there, add a matching mock under `PagelessTests/Mocks/`.
