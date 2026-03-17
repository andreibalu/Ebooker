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

### Data Layer (SwiftData)
Three models: `Audiobook` → `AudioTrack[]` + `Moment[]`. Audio files are stored in `Application Support/Audiobooks/[UUID]/`. Cover images use SwiftData external storage.

### Central State: `AudioPlayerManager`
`AudioPlayerManager` (ObservableObject) is the single source of truth for all playback state. It's injected via `@EnvironmentObject` and handles:
- AVPlayer orchestration, track queuing, background modes
- Progress persistence and high-water mark tracking (furthest point reached, separate from current position)
- Seek penalty logic (prevents progress inflation from manual seeks)
- Remote Command Center integration (Control Center, headphone controls)
- 1-second periodic time observer for live progress updates

### AI & On-Device Intelligence
- `MomentNamingService` — uses `FoundationModels.SystemLanguageModel` (Apple Intelligence) for generating moment names
- `TranscriptionService` — Speech framework wrapper for audio transcription
- `AppleIntelligenceCapability` — checks device/model capability at runtime before using AI features
- Requires iOS 18+ (Apple Intelligence only available on eligible devices/models)

### View Hierarchy
```
ContentView (library grid, favorites tab)
├── AudiobookCardView (grid cell)
├── AudiobookDetailView (tracks + moments tabs, cover editing via PhotosPicker)
├── PlayerView (full-screen player, moment saving with optional AI naming)
├── MiniPlayerBar (persistent bottom bar when playing)
└── SettingsView (playback preferences via @AppStorage)
```

### Settings & Preferences
User preferences live in `@AppStorage` and are typed via enums in `PlaybackSettings.swift`: `LibrarySortOption`, `ResumeBacktrackOption`, `SkipIntervalOption`, `MomentBacktrackOption`, `SleepTimerOption`.

## Key Patterns

- **SwiftData queries**: Use `@Query` in views; pass `modelContext` explicitly to services
- **File access**: Always use security-scoped access (`startAccessingSecurityScopedResource`) for user-imported files
- **Async bridging**: Use `withCheckedContinuation` when bridging completion-handler APIs (e.g., Speech framework)
- **Flat file structure**: All Swift source files live directly in `Ebooker/` (subdirectories exist but are empty)

## Testing

Tests use Swift Testing framework (`import Testing`). Test targets (`EbookerTests`, `EbookerUITests`) are currently boilerplate stubs.
