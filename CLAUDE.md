# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Identity

- **Marketing name (App Store / home screen)**: Unpaged
- **Xcode scheme**: `Ebooker`
- **Source module folder**: `Pageless/`
- **Bundle identifier prefix**: `andreibaludev.Pageless`
- **Current marketing version**: see `VERSION` (1.1)

The three names are intentional historical layers — do not "fix" them. New user-facing copy should say "Unpaged".

## Build & Run

Use XcodeBuildMCP tools for all build/run operations:

- **Build & run on simulator**: `mcp__XcodeBuildMCP__build_run_sim` (scheme: `Ebooker`)
- **Build only**: `mcp__XcodeBuildMCP__build_sim`
- **Run tests**: `mcp__XcodeBuildMCP__test_sim`
- **Clean**: `mcp__XcodeBuildMCP__clean`

Always call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/simulator settings before building.

**Device target**: Always build and run on **Andrei's iPhone 15** (personal device) — use `mcp__XcodeBuildMCP__build_run_device` / `mcp__XcodeBuildMCP__build_device` instead of simulator tools when running on device. Use the `xcode-device-build` skill if needed for device setup.

The project has no external package dependencies — it uses only native Apple frameworks (AVFoundation, MediaToolbox, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, Intents, CarPlay, Network).

## Info.plist Highlights (App Store relevant)

- `CFBundleDisplayName`: `Unpaged`
- `ITSAppUsesNonExemptEncryption`: `false`
- `NSMicrophoneUsageDescription` — for CarPlay voice search
- `NSSpeechRecognitionUsageDescription` — for transcription, AI moment naming, and CarPlay voice search
- `UIBackgroundModes`: `audio`
- Two scene roles registered: `UIWindowScene` (default) and `CPTemplateApplicationScene` → `CarPlaySceneDelegate`
- Orientations: portrait + both landscapes on iPhone; all four on iPad

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers (CarPlay is the one exception: `CarPlayCoordinator`).

### Folder Structure

```
Pageless/
├── App/
│   ├── PagelessApp.swift          @main; ModelContainer, scene wiring, env injection, voice-permission priming, Siri shortcut handoff
│   ├── AppDelegate.swift          Owns ModelContainer, AudioPlayerManager, FreeBookDownloadService; background URLSession handler; CarPlay scene config
│   └── CarPlaySceneDelegate.swift CarPlay interface controller connector
├── AppIntents/
│   └── AudiobookIntents.swift     `PlayLatestBookIntent` + `UnpagedAppShortcuts` provider ("Play Latest Book")
├── Configuration/
│   └── AIProductID.swift          StoreKit product ID constant for AI unlock
├── Models/
│   ├── Audiobook.swift            SwiftData @Model; playback, progress marker, recap, EQ, streaming-vs-downloaded, free-book metadata
│   ├── AudioTrack.swift           SwiftData @Model; per-track metadata (supports remote URLs for streaming)
│   ├── Moment.swift               SwiftData @Model; bookmarks with AI metadata
│   ├── MomentEnums.swift          `MomentCategory` (10 types), `MomentMood` (8 types)
│   ├── PlaybackSettings.swift     `LibrarySortOption`, `SkipIntervalOption`, `ResumeBacktrackOption`, `MomentBacktrackOption`, `SleepTimerOption`
│   ├── EqualizerSettings.swift    `EqualizerBand`, `EqualizerPreset` (flat/voiceBoost/bassBoost/trebleBoost/podcast/custom), `EqualizerConfiguration`
│   ├── LibriVoxBook.swift         SwiftData @Model for the cached LibriVox catalog (20k+ rows)
│   ├── CachedLibriVoxTrack.swift  Lightweight non-persisted track snapshot embedded JSON-encoded inside `LibriVoxBook.cachedTracks`
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
│   ├── SettingsView.swift         Playback preferences
│   ├── AISettingsView.swift       AI feature toggles, trial management, IAP unlock
│   ├── CoverCropView.swift        Image cropping interface for cover art
│   ├── EqualizerSheet.swift       5-band EQ + preamp + presets UI; mounted from player
│   ├── FreeBooks/
│   │   ├── BrowseLibriVoxView.swift       Search + filters + featured + active downloads
│   │   ├── LibriVoxBookDetailView.swift   Cover/metadata, sample preview, download/add-to-library
│   │   └── LibriVoxBookRow.swift          Search result row with inline sample button
│   └── Onboarding/
│       ├── OnboardingStep.swift          Enum defining 7 onboarding phases
│       └── SpotlightOverlayView.swift    Spotlight tutorial overlay
├── Services/
│   ├── Protocols/
│   │   ├── TranscriptionProviding.swift
│   │   ├── MomentAnalyzing.swift
│   │   ├── AudioExtracting.swift
│   │   ├── RecapProviding.swift               (defines `RecapGenerationResult`)
│   │   └── FreeBookDownloading.swift          (legacy seed-catalog download protocol)
│   ├── AudioPlayerManager.swift            Central playback state (ObservableObject); owns `equalizer: AudioEqualizerService`
│   ├── PlaybackPersistence.swift           Progress tracking, high-water mark, SwiftData saves
│   ├── NowPlayingUpdater.swift             MPRemoteCommandCenter + MPNowPlayingInfoCenter
│   ├── LibraryImportService.swift          User-file import with security-scoped access (enum + static methods)
│   ├── TranscriptionService.swift          Speech framework wrapper
│   ├── MomentNamingService.swift           FoundationModels AI moment analysis
│   ├── RecapService.swift                  FoundationModels progress recap generation
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
│   ├── AppleIntelligenceCapability.swift   Runtime AI feature detection
│   └── AIEntitlementStore.swift            StoreKit 2 IAP + trial-use tracking
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
├── ServiceTests/
│   ├── AudioEqualizerServiceTests.swift
│   ├── AudioPlayerManagerSkipTests.swift
│   ├── AudioSessionInterruptionTests.swift
│   ├── AudiobookSavedProgressResumeTests.swift
│   ├── FreeBookCatalogServiceTests.swift
│   ├── FreeBookDownloadServiceTests.swift
│   ├── MomentNamingServiceLogicTests.swift
│   ├── NowPlayingUpdaterTests.swift
│   ├── OnboardingManagerTests.swift
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

**Four models** registered in the `ModelContainer` (see `AppDelegate.swift`): `Audiobook`, `AudioTrack`, `Moment`, `LibriVoxBook`.

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
└── id, title, originalFileName, storedFileName, orderIndex, duration, audiobook?

Moment (@Model final)
├── id, trackIndex, time, createdAt
├── label, transcript?, aiGeneratedName, notes, isPinned
├── AI fields (JSON-serialized): categories[], quoteLine?, characters[], mood?
└── audiobook?

LibriVoxBook (@Model final)
├── id (unique), title, authorDisplay, bookDescription, language, totalTimeSecs
├── genres (JSON-backed), cachedTracks (JSON-backed [CachedLibriVoxTrack]), cover URLs, RSS URL
└── Computed: formattedDuration, estimatedDownloadSizeMB, bestCoverURL
```

**Schema evolution**: New columns use private backing fields with computed getters/setters (e.g., `_isFavorite`, `_isFreeBook`, `_isDownloaded`, `_progressRecap*`, `_eqBandGainsJSON`, `_eqPresetRaw`) for SwiftData lightweight migration. All post-launch fields are nullable on disk and given safe defaults in the computed accessor.

## Central State: `AudioPlayerManager`

`AudioPlayerManager` (ObservableObject) is the single source of truth for all playback state, injected via `@EnvironmentObject`. It exposes its `equalizer: AudioEqualizerService` as a separate `@EnvironmentObject` so views can bind to EQ controls without going through the player.

Responsibilities:
- AVPlayer orchestration, track queuing, background audio modes
- Builds per-item `AVAudioMix` via `AudioEqualizerService.makeAudioMix(for:)` so the EQ tap runs in the audio pipeline
- Delegates persistence to `PlaybackPersistence` (progress saves, high-water mark, seek penalty)
- Delegates remote commands to `NowPlayingUpdater` (Control Center, headphone controls, CarPlay now-playing)
- 1-second periodic time observer for live progress updates
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
| `MomentAnalyzing` | `MomentNamingService` | FoundationModels |
| `RecapProviding` | `RecapService` | FoundationModels |
| `AudioExtracting` | `AudioExtractionService` | AVFoundation (AVAssetExportSession) |
| `FreeBookDownloading` | `FreeBookDownloadService` | URLSession (background) — legacy seed catalog |

## AI & On-Device Intelligence

- `MomentNamingService: MomentAnalyzing` — AI moment analysis: name, note, categories, quoteLine, characters, mood
- `RecapService: RecapProviding` — generates `RecapGenerationResult` (recap text + optional `progressHeadline`)
- `TranscriptionService: TranscriptionProviding` — Speech framework wrapper with `withCheckedContinuation` bridge
- `AppleIntelligenceCapability` — runtime detection for showing/hiding AI UI buttons
- `AIEntitlementStore` — StoreKit 2: trial uses tracking + IAP unlock (`AIProductID`)
- AI features are isolated behind protocols; app works fully without Apple Intelligence

## Feature Systems

### Free Books — two parallel systems

The app contains **two independent free-book paths** that coexist by design:

1. **LibriVox catalog (primary, iPhone)** — 20,000+ books from librivox.org. Cached locally in `LibriVoxBook` via `LibriVoxCatalogSync` (24h incremental sync). UI is the "Free Books" tab in `ContentView`, driven by `BrowseLibriVoxView` → `LibriVoxBookDetailView`. Supports:
   - **Add to Library (streaming)** via `StreamingLibraryService` — creates an `Audiobook` with `isDownloaded == false` and remote URLs on each `AudioTrack`. No files written. Requires network at playback time.
   - **Download** via `LibriVoxDownloadService` — fetches all tracks + cover, creates a normal local `Audiobook`. Also used by `StreamedBookDownloadViewModel` to promote an already-added streaming book to downloaded.
   - **Sample preview** via `SamplePlayer` — 20s preview of a track without committing.
   - **Network gating** — `NetworkMonitor.shared.isConnected` checked before sample play, sync, and streaming.

2. **Legacy seed catalog (CarPlay)** — `FreeBookCatalogService` exposes 5 hand-picked Internet Archive classics. Downloaded via `FreeBookDownloadService` (background URLSession with published `downloadProgress`, `activeDownloads`, `downloadErrors`). Consumed only by `CarPlayCoordinator` and `LibraryViewModel`. **Do not extend this path for new iPhone features — use the LibriVox path.**

### Equalizer (per-book)

- `EqualizerSettings` defines the data model: 5 bands (60Hz / 250Hz / 1kHz / 4kHz / 14kHz), presets (flat, voiceBoost, bassBoost, trebleBoost, podcast, custom), preamp 0–12 dB, band gain ±12 dB
- `EqualizerTap` is a C-level `MTAudioProcessingTap` running biquad filters + a soft limiter on the realtime audio thread; coefficients updated under `os_unfair_lock`
- `AudioEqualizerService` (`ObservableObject`) holds the live `@Published` state, persists it to the current `Audiobook.equalizerConfiguration`, and builds the `AVAudioMix` injected into each `AVPlayerItem`
- `EqualizerSheet` is the user-facing UI; reads/writes via `@EnvironmentObject AudioEqualizerService`

### Onboarding
- `OnboardingManager` — 4 phases: `phase1`, `waitingForBook`, `phase2`, `completed` (UserDefaults persistence)
- `OnboardingStep` — 7 steps: `p1AddButton`, `p1Settings`, `p1AILink`, `p1AIPage`, `p1DeviceCapability`, `p2Progress`, `p2Moments`
- `SpotlightOverlayView` — spotlight tutorial overlay rendered over content

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
- **AI isolation**: `AppleIntelligenceCapability` guards UI visibility; ViewModels catch service errors and fall back gracefully.
- **Schema migration**: Private backing field pattern (`_fieldName`) with computed getter/setter for post-launch columns; new fields nullable on disk.
- **Streaming vs downloaded**: Treat `Audiobook.isStreamingOnly` as load-bearing — anything that touches the on-disk path must check it. Promotion to downloaded goes through `LibriVoxDownloadService`.
- **CarPlay permission constraint**: Mic + speech permission prompts cannot appear on the CarPlay screen, so `VoiceSearchPermissions.primeIfNeeded()` runs at iPhone launch. Don't add new permission requests that can fire only on CarPlay.

## Testing

Tests use Swift Testing framework (`import Testing`). To run: use `mcp__XcodeBuildMCP__test_sim` or `xcodebuild test`.

Mock implementations live in `PagelessTests/Mocks/`:
- `MockTranscriptionService`, `MockMomentAnalyzer`, `MockRecapService`, `MockAudioExtractor`, `MockFreeBookDownloadService`

All protocol-backed services have corresponding mocks for ViewModel tests. New LibriVox-path code is currently exercised through integration-style tests against SwiftData in-memory containers rather than via mocks — if you add a new protocol there, add a matching mock under `PagelessTests/Mocks/`.
