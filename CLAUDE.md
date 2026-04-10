# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Use XcodeBuildMCP tools for all build/run operations:

- **Build & run on simulator**: `mcp__XcodeBuildMCP__build_run_sim` (scheme: `Ebooker`)
- **Build only**: `mcp__XcodeBuildMCP__build_sim`
- **Run tests**: `mcp__XcodeBuildMCP__test_sim`
- **Clean**: `mcp__XcodeBuildMCP__clean`

Always call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/simulator settings before building.

**Device target**: Always build and run on **Andrei's iPhone 15** (personal device) — use `mcp__XcodeBuildMCP__build_run_device` / `mcp__XcodeBuildMCP__build_device` instead of simulator tools when running on device. Use the `xcode-device-build` skill if needed for device setup.

The project has no external package dependencies — it uses only native Apple frameworks (AVFoundation, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, Intents).

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers.

The Xcode scheme is `Ebooker`; the source module folder is `Pageless/`.

### Folder Structure

```
Pageless/
├── App/
│   ├── PagelessApp.swift          Entry point, ModelContainer setup, scene configuration
│   ├── AppDelegate.swift          Background URLSession handler, CarPlay scene config
│   └── CarPlaySceneDelegate.swift CarPlay interface controller connector
├── Models/
│   ├── Audiobook.swift            SwiftData @Model, root entity with playback state
│   ├── AudioTrack.swift           SwiftData @Model for individual tracks
│   ├── Moment.swift               SwiftData @Model for bookmarks with AI metadata
│   ├── FreeBookCatalogEntry.swift Non-persisted struct for free book catalog metadata
│   ├── MomentEnums.swift          MomentCategory (10 types), MomentMood (8 types)
│   └── PlaybackSettings.swift     Preference enums (LibrarySortOption, SkipIntervalOption, etc.)
├── ViewModels/
│   ├── PlayerViewModel.swift      Moment creation state, smart save workflow
│   ├── AudiobookDetailViewModel.swift  Moment filtering, recap generation
│   └── LibraryViewModel.swift     Import workflow, delete/rename, free book downloads
├── Views/
│   ├── ContentView.swift          Root library (Favorites/All Books tabs, free books section)
│   ├── PlayerView.swift           Full-screen player with controls and moment saving
│   ├── AudiobookDetailView.swift  Tracks list, moments grid, recap display, cover editing
│   ├── AudiobookCardView.swift    Library grid cell
│   ├── AudiobookTrackRow.swift    Track list item
│   ├── MiniPlayerBar.swift        Persistent bottom playback bar
│   ├── MomentRow.swift            Moment list item with play/edit actions
│   ├── MomentEditSheet.swift      Modal for naming moments, AI-generated metadata display
│   ├── MomentFilterSheet.swift    Category/character/mood filtering UI
│   ├── FreeBookCardView.swift     Free book catalog card
│   ├── FreeBookDetailSheet.swift  Free book details and download controls
│   ├── ImportAudiobookSheet.swift Import workflow with file preview
│   ├── SettingsView.swift         Playback preferences
│   ├── AISettingsView.swift       AI feature toggles, trial management
│   ├── CoverCropView.swift        Image cropping interface for cover art
│   └── Onboarding/
│       ├── OnboardingStep.swift   Enum defining 7 onboarding phases
│       └── SpotlightOverlayView.swift  Spotlight tutorial overlay
├── Services/
│   ├── Protocols/
│   │   ├── TranscriptionProviding.swift
│   │   ├── MomentAnalyzing.swift
│   │   ├── AudioExtracting.swift
│   │   ├── RecapProviding.swift   Includes RecapGenerationResult struct
│   │   └── FreeBookDownloading.swift
│   ├── AudioPlayerManager.swift   Central playback state (ObservableObject)
│   ├── PlaybackPersistence.swift  Progress tracking, high-water mark, SwiftData saves
│   ├── NowPlayingUpdater.swift    MPRemoteCommandCenter, MPNowPlayingInfoCenter
│   ├── LibraryImportService.swift File import with security-scoped access (enum, static methods)
│   ├── TranscriptionService.swift Speech framework wrapper
│   ├── MomentNamingService.swift  FoundationModels AI moment analysis
│   ├── RecapService.swift         FoundationModels progress recap generation
│   ├── AudioExtractionService.swift  AVAssetExportSession audio segment extraction
│   ├── FreeBookCatalogService.swift  Fetches free book catalog from Internet Archive
│   ├── FreeBookDownloadService.swift Background URLSession download management
│   ├── OnboardingManager.swift    Multi-phase onboarding state (UserDefaults)
│   ├── CarPlayCoordinator.swift   CarPlay UI templates and now-playing integration
│   ├── AudiobookSavedProgressResume.swift  Resume-from-bookmark logic enum
│   ├── AppleIntelligenceCapability.swift   Runtime AI feature detection
│   └── AIEntitlementStore.swift   StoreKit 2 IAP and trial use tracking
├── AppIntents/
│   └── AudiobookIntents.swift     Siri shortcut: "Play Latest Book"
├── Configuration/
│   └── AIProductID.swift          StoreKit product ID constant for AI unlock
└── Utilities/
    ├── TimeFormatter.swift        Clock string formatting, duration summaries
    └── Color+Theme.swift          Cream/cardWhite theme colors with dark mode support

PagelessTests/
├── Mocks/
│   ├── MockTranscriptionService.swift
│   ├── MockMomentAnalyzer.swift
│   ├── MockRecapService.swift
│   ├── MockAudioExtractor.swift
│   └── MockFreeBookDownloadService.swift
├── ModelTests/
│   ├── AudiobookTests.swift
│   ├── AudioTrackTests.swift
│   ├── MomentTests.swift
│   ├── AudiobookFreeBookTests.swift
│   ├── AudiobookAdditionalTests.swift
│   └── FreeBookCatalogEntryTests.swift
├── ServiceTests/
│   ├── PlaybackPersistenceTests.swift
│   ├── PlaybackPersistenceRecapTests.swift  (in ServicesTests/)
│   ├── AudiobookSavedProgressResumeTests.swift
│   ├── OnboardingManagerTests.swift
│   ├── FreeBookCatalogServiceTests.swift
│   ├── FreeBookDownloadServiceTests.swift
│   ├── NowPlayingUpdaterTests.swift
│   ├── AudioSessionInterruptionTests.swift
│   ├── RecapServiceLogicTests.swift
│   ├── MomentNamingServiceLogicTests.swift
│   └── SiriIntentTests.swift
└── ViewModelTests/
    ├── PlayerViewModelTests.swift
    ├── PlayerViewModelCommitTests.swift
    ├── AudiobookDetailViewModelTests.swift
    ├── AudiobookDetailViewModelFilterTests.swift
    ├── LibraryViewModelTests.swift
    └── LibraryViewModelFreeBookTests.swift

PagelessUITests/
├── PagelessUITests.swift
└── PagelessUITestsLaunchTests.swift
```

## Data Layer (SwiftData)

Three models: `Audiobook` → `AudioTrack[]` + `Moment[]`. Audio files stored at `Application Support/Audiobooks/[UUID]/`. Cover images use SwiftData external storage.

```
Audiobook (@Model final)
├── id: UUID
├── Playback state: currentTrackIndex, currentTime, playbackRate, isFinished
├── Progress marker: progressTrackIndex?, progressTime?, progressUpdatedAt?
├── Progress recap: progressRecapText?, progressRecapHeadline?, progressRecapAnchorTrackIndex?, progressRecapAnchorTime?
├── Metadata: title, author, folderName, coverArtData (external storage), createdAt, lastPlayedAt, isFavorite, isFreeBook, catalogId
├── Computed: listenedDuration, progress, remainingDuration, currentTrackTitle, displayAuthor, castList
└── @Relationship: tracks[] + moments[] (both cascade delete)

AudioTrack (@Model final)
└── id, title, originalFileName, storedFileName, orderIndex, duration, audiobook?

Moment (@Model final)
├── id, trackIndex, time, createdAt
├── label, transcript?, aiGeneratedName, notes, isPinned
├── AI fields (JSON-serialized): categories[], quoteLine?, characters[], mood?
└── audiobook?
```

**Schema evolution**: New columns use private backing fields with computed getters/setters (e.g., `_isFavorite`, `_categoriesRaw`) for lightweight migration. All post-launch fields are nullable.

## Central State: `AudioPlayerManager`

`AudioPlayerManager` (ObservableObject) is the single source of truth for all playback state, injected via `@EnvironmentObject`. Responsibilities:
- AVPlayer orchestration, track queuing, background audio modes
- Delegates persistence to `PlaybackPersistence` (progress saves, high-water mark, seek penalty)
- Delegates remote commands to `NowPlayingUpdater` (Control Center, headphone controls)
- 1-second periodic time observer for live progress updates

## ViewModels

Three `@MainActor @Observable` ViewModels. Views create them with `@State`. Services are injected via initializers with protocol types (default implementations provided).

| ViewModel | Key State | Services |
|-----------|-----------|----------|
| `PlayerViewModel` | `pendingMomentTime`, `momentNameInput`, `pendingCategories`, `pendingCharacters`, `pendingMood`, `pendingQuoteLine` | `TranscriptionProviding`, `MomentAnalyzing`, `AudioExtracting` |
| `AudiobookDetailViewModel` | `filterCategories`, `filterCharacters`, `filterMoods`, `isLoadingRecap`, `recapText`, `recapProgressHeadline` | `TranscriptionProviding`, `AudioExtracting`, `RecapProviding` |
| `LibraryViewModel` | `pendingImport`, `urlsHoldingSecurityAccess`, `deleteCandidate`, `renameCandidate` | `FreeBookDownloading` |

## Services

Protocol implementations are `struct` types. `LibraryImportService` is a concrete `enum` with static methods (file management, used directly by `AudioPlayerManager` and ViewModels).

| Protocol | Implementation | Framework |
|----------|---------------|-----------|
| `TranscriptionProviding` | `TranscriptionService` | Speech |
| `MomentAnalyzing` | `MomentNamingService` | FoundationModels |
| `RecapProviding` | `RecapService` | FoundationModels |
| `AudioExtracting` | `AudioExtractionService` | AVFoundation (AVAssetExportSession, 50s segments) |
| `FreeBookDownloading` | `FreeBookDownloadService` | URLSession (background) |

## AI & On-Device Intelligence

- `MomentNamingService: MomentAnalyzing` — AI moment analysis: name, note, categories, quoteLine, characters, mood
- `RecapService: RecapProviding` — generates `RecapGenerationResult` (recap text + optional `progressHeadline`)
- `TranscriptionService: TranscriptionProviding` — Speech framework wrapper with `withCheckedContinuation` bridge
- `AppleIntelligenceCapability` — runtime detection for showing/hiding AI UI buttons
- `AIEntitlementStore` — StoreKit 2: trial uses tracking + IAP unlock (`AIProductID`)
- AI features are isolated behind protocols; app works fully without Apple Intelligence

## Feature Systems

### Free Books
- `FreeBookCatalogService` — fetches catalog from Internet Archive (5 classics: Christmas Carol, Alice in Wonderland, Frankenstein, The Metamorphosis, The Picture of Dorian Gray)
- `FreeBookDownloadService` — background URLSession with published `downloadProgress`, `activeDownloads`, `downloadErrors`
- `FreeBookDownloading` protocol enables mock testing
- UI: `FreeBookCardView`, `FreeBookDetailSheet` in `ContentView`

### Onboarding
- `OnboardingManager` — 4 phases: `phase1`, `waitingForBook`, `phase2`, `completed` (UserDefaults persistence)
- `OnboardingStep` — 7 steps: `p1AddButton`, `p1Settings`, `p1AILink`, `p1AIPage`, `p1DeviceCapability`, `p2Progress`, `p2Moments`
- `SpotlightOverlayView` — spotlight tutorial overlay rendered over content

### CarPlay
- `CarPlaySceneDelegate` — connects CarPlay scene to `CarPlayCoordinator`
- `CarPlayCoordinator` — full CarPlay UI templates, now-playing, moment saving
- `AppDelegate` — background URL session handler + CarPlay scene registration

### Siri / App Intents
- `AudiobookIntents.swift` — `PlayLatestBookIntent` (Siri shortcut: "Play Latest Book")

## View Hierarchy

```
PagelessApp (@main)
└── WindowGroup → ContentView (LibraryViewModel)
    ├── NavigationStack
    │   ├── libraryHeader (sort options)
    │   ├── tabPicker (Favorites / All Books)
    │   └── LazyVGrid → AudiobookCardView[] → AudiobookDetailView (AudiobookDetailViewModel)
    │       ├── resumeAnchorRow (play from progress or recap)
    │       ├── MomentRow[] → MomentEditSheet
    │       ├── MomentFilterSheet
    │       └── AudiobookTrackRow[]
    ├── freeBooksSection → FreeBookCardView[] → FreeBookDetailSheet
    ├── MiniPlayerBar (when currentAudiobook != nil)
    ├── PlayerView (.sheet, full-screen) → PlayerViewModel
    │   └── MomentEditSheet (.sheet)
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

- **MVVM**: Views own `@Query`, `@AppStorage`, UI state. ViewModels own business state and async workflows. Services are stateless and injectable.
- **Dependency injection**: Initializer injection on ViewModels with protocol-typed services; default implementations provided so views can call `ViewModel()` without arguments.
- **SwiftData queries**: Use `@Query` in views; pass `modelContext` explicitly to ViewModels/services.
- **File access**: Always use security-scoped access (`startAccessingSecurityScopedResource`) for user-imported files. Release access in `LibraryViewModel.releaseSecurityScopedAccess()`.
- **Async bridging**: Use `withCheckedContinuation` / `withCheckedThrowingContinuation` when bridging completion-handler APIs (Speech framework).
- **AI isolation**: `AppleIntelligenceCapability` guards UI visibility; ViewModels catch service errors and fall back gracefully.
- **Schema migration**: Private backing field pattern (`_fieldName`) with computed getter/setter for post-launch columns; new fields nullable.

## Testing

Tests use Swift Testing framework (`import Testing`). 30 test files total.

To run tests: use `mcp__XcodeBuildMCP__test_sim` or `xcodebuild test`.

Mock implementations live in `PagelessTests/Mocks/`:
- `MockTranscriptionService`, `MockMomentAnalyzer`, `MockRecapService`, `MockAudioExtractor`, `MockFreeBookDownloadService`

All protocol-backed services have corresponding mocks for ViewModel tests.
