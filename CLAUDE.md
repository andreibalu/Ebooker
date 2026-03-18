# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Use XcodeBuildMCP tools for all build/run operations:

- **Build & run on simulator**: `mcp__XcodeBuildMCP__build_run_sim` (scheme: `Ebooker`)
- **Build only**: `mcp__XcodeBuildMCP__build_sim`
- **Run tests**: `mcp__XcodeBuildMCP__test_sim`
- **Clean**: `mcp__XcodeBuildMCP__clean`

Always call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/simulator settings before building.

The project has no external package dependencies — it uses only native Apple frameworks (AVFoundation, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI).

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers.

### Folder Structure
```
Ebooker/
├── App/               EbookerApp.swift (entry point, container setup)
├── Models/            SwiftData models + enums (Audiobook, AudioTrack, Moment, PlaybackSettings)
├── Services/          Business logic & platform integration
│   ├── Protocols/     Service protocols (TranscriptionProviding, MomentAnalyzing, RecapProviding, AudioExtracting)
│   ├── AudioPlayerManager.swift   (central playback state, ObservableObject)
│   ├── PlaybackPersistence.swift  (progress tracking, SwiftData saves)
│   ├── NowPlayingUpdater.swift    (MPRemoteCommandCenter, MPNowPlayingInfoCenter)
│   ├── LibraryImportService.swift (file import, security-scoped access)
│   └── ...            (TranscriptionService, MomentNamingService, RecapService, etc.)
├── ViewModels/        @Observable ViewModels (PlayerViewModel, AudiobookDetailViewModel, LibraryViewModel)
├── Views/             SwiftUI views (ContentView, PlayerView, AudiobookDetailView, etc.)
└── Utilities/         TimeFormatter, Color+Theme
```

### Data Layer (SwiftData)
Three models: `Audiobook` → `AudioTrack[]` + `Moment[]`. Audio files are stored in `Application Support/Audiobooks/[UUID]/`. Cover images use SwiftData external storage.

### Central State: `AudioPlayerManager`
`AudioPlayerManager` (ObservableObject) is the single source of truth for all playback state. It's injected via `@EnvironmentObject` and handles:
- AVPlayer orchestration, track queuing, background modes
- Delegates persistence to `PlaybackPersistence` (progress saves, high-water mark, seek penalty)
- Delegates remote commands to `NowPlayingUpdater` (Control Center, headphone controls)
- 1-second periodic time observer for live progress updates

### ViewModels
Three `@Observable` ViewModels extract business logic from views:
- **`PlayerViewModel`** — moment creation state, smart save workflow (extract → transcribe → AI analyze)
- **`AudiobookDetailViewModel`** — moment filtering, recap generation workflow
- **`LibraryViewModel`** — import workflow, delete/rename, sorting

ViewModels receive protocol-typed service dependencies via initializer injection. Views create ViewModels with `@State`.

### Services
Services are `struct` types conforming to protocols (`TranscriptionProviding`, `MomentAnalyzing`, `RecapProviding`, `AudioExtracting`). This enables mock injection for testing.

`LibraryImportService` remains a concrete `enum` with static methods — it handles file management and is used directly by `AudioPlayerManager` and ViewModels.

### AI & On-Device Intelligence
- `MomentNamingService: MomentAnalyzing` — uses `FoundationModels.SystemLanguageModel` for moment analysis
- `RecapService: RecapProviding` — generates recaps of recent listening
- `TranscriptionService: TranscriptionProviding` — Speech framework wrapper
- `AppleIntelligenceCapability` — runtime feature detection (UI guard for showing/hiding AI buttons)
- AI features are isolated behind protocols; app works fully without Apple Intelligence

### View Hierarchy
```
ContentView (library grid, favorites tab) → LibraryViewModel
├── AudiobookCardView (grid cell)
├── AudiobookDetailView (tracks + moments tabs, cover editing) → AudiobookDetailViewModel
│   ├── AudiobookTrackRow (track list item)
│   ├── MomentRow (moment list item with edit sheet)
│   └── MomentFilterSheet (category/character/mood filtering)
├── PlayerView (full-screen player, moment saving) → PlayerViewModel
├── MiniPlayerBar (persistent bottom bar when playing)
└── SettingsView (playback preferences via @AppStorage)
```

### Settings & Preferences
User preferences live in `@AppStorage` and are typed via enums in `PlaybackSettings.swift`: `LibrarySortOption`, `ResumeBacktrackOption`, `SkipIntervalOption`, `MomentBacktrackOption`, `SleepTimerOption`.

## Key Patterns

- **MVVM**: Views own `@Query`, `@AppStorage`, UI state. ViewModels own business state and async workflows. Services are stateless and injectable.
- **Dependency injection**: Initializer injection on ViewModels with protocol-typed services. No DI container.
- **SwiftData queries**: Use `@Query` in views; pass `modelContext` explicitly to ViewModels/services
- **File access**: Always use security-scoped access (`startAccessingSecurityScopedResource`) for user-imported files
- **Async bridging**: Use `withCheckedContinuation` when bridging completion-handler APIs (e.g., Speech framework)
- **AI isolation**: `AppleIntelligenceCapability` guards UI visibility; ViewModels catch service errors and fall back gracefully

## Testing

Tests use Swift Testing framework (`import Testing`). Test structure:
```
EbookerTests/
├── Mocks/              Mock service implementations (MockTranscriptionService, MockMomentAnalyzer, etc.)
├── ViewModelTests/     PlayerViewModelTests, AudiobookDetailViewModelTests, LibraryViewModelTests
├── ServiceTests/       PlaybackPersistenceTests
└── ModelTests/         AudiobookTests
```

To run tests: use `mcp__XcodeBuildMCP__test_sim` or `xcodebuild test`.
