# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repo.

## App Identity

- **Marketing name (App Store / home screen)**: Unpaged
- **Xcode scheme**: `Pageless` · **source folder**: `Pageless/` · **bundle id prefix**: `andreibaludev.Pageless`
- **Marketing version**: see `VERSION` (currently 1.3)

Three names = intentional historical layers — no "fix". New user-facing copy says "Unpaged".

## External-facing docs

`support.md`, `privacy-policy.md`, `EULA.md` in repo root back the App Store Support / Privacy / EULA URLs (hosted as public GitHub Gists; repo = source of truth). Update in the same commit when a change touches:

- Permissions (`Info.plist` `NS*UsageDescription`) → support + privacy
- Network behavior, third-party services, data collected → privacy-policy
- AI features, IAP terms, trial mechanics → all three (EULA §3 carries subscription/IAP terms)
- Min iOS / supported devices / new user-visible features → support
- Contact email or developer name → all three (spell "Andrei Baluta" identically)

After editing, remind the user to push the new content to the public Gist(s).

## Build & Run

XcodeBuildMCP for all build/run. Only device tools enabled in this MCP profile — no `*_sim` variants. Call `mcp__XcodeBuildMCP__session_show_defaults` first to verify project/scheme/device.

- **Build & run**: `mcp__XcodeBuildMCP__build_run_device` (scheme `Pageless`)
- **Build only**: `mcp__XcodeBuildMCP__build_device`
- **Tests**: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]` (Mac can't handle parallel destinations)
- **Clean**: `mcp__XcodeBuildMCP__clean`

**Device target**: always Andrei's iPhone 15 Pro — identifier `00008130-000471A80C81001C` (UDID `BAE98D59-834B-5B20-8E9A-8943DCE6F7FD`). Apple Intelligence (`FoundationModels`) only runs on 15 Pro / 16+ hardware, so the simulator can't exercise AI surfaces. `xcode-device-build` skill helps with device setup.

**External packages: none.** Native Apple frameworks only (AVFoundation, MediaToolbox, SwiftData, Speech, FoundationModels, MediaPlayer, PhotosUI, StoreKit, Intents, CarPlay, Network). RevenueCat was removed — see "In-App Purchases".

## Info.plist / Target Settings (App Store relevant)

- `ITSAppUsesNonExemptEncryption: false`; `UIBackgroundModes: audio`
- Mic + speech usage descriptions (CarPlay voice search; transcription + AI moment naming)
- Two scene roles: `UIWindowScene` (default) + `CPTemplateApplicationScene` → `CarPlaySceneDelegate`
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `TARGETED_DEVICE_FAMILY = 1` (iPhone-only). AI features gated `@available(iOS 26, *)` + runtime-checked, so the binary installs and runs on iOS 18+ with AI surfaces auto-hidden below iOS 26.

## Architecture

**Lightweight MVVM** with protocol-based services. No coordinators or DI containers (one exception: `CarPlayCoordinator`).

```
Pageless/
├── App/             PagelessApp (@main; scene wiring, voice-permission priming, Siri handoff),
│                    AppDelegate (ModelContainer; re-runs orphan detection on CloudKit import batches),
│                    CarPlaySceneDelegate
├── AppIntents/      AudiobookIntents — `PlayLatestBookIntent` + `UnpagedAppShortcuts`
├── Configuration/   AIProductID (both IAP ids), Products.storekit (local StoreKit test config)
├── Models/          SwiftData models + settings/stats enums (see Data Layer)
├── ViewModels/      six ViewModels (see table)
├── Views/           ContentView (root tabs + per-tab sort + header iCloud button), player /
│                    detail / settings / cloud / moment views; subfolders FreeBooks/,
│                    ReadingStats/, Onboarding/
├── Services/        playback, import/AI, stats, EQ, LibriVox, CarPlay, IAP, iCloud sync
│   └── Protocols/   TranscriptionProviding, MomentAnalyzing, AudioExtracting, RecapProviding,
│                    FreeBookDownloading (iOS<26 `Unavailable…` fallbacks live here too)
└── Utilities/       TimeFormatter, BookDescriptionFormatting, Color+Theme (`amber` accent)
```

`PagelessTests/` — Swift Testing: Mocks/ (one per protocol service), ModelTests/, ServiceTests/, ViewModelTests/; SchemaCompatibilityTests validates CloudKit constraints. `PagelessUITests/` — launch + UI tests.

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

## ViewModels

All `@MainActor @Observable`; views create them with `@State`. Initializer injection with protocol-typed services, concrete defaults provided so `ViewModel()` works without arguments.

| ViewModel | Key State | Services |
|-----------|-----------|----------|
| `PlayerViewModel` | pending moment fields (time/name/categories/characters/mood/quoteLine), smart-save warning | `TranscriptionProviding`, `MomentAnalyzing`, `AudioExtracting` |
| `AudiobookDetailViewModel` | moment filters, `isLoadingRecap`, `recapText`, `recapProgressHeadline` | `TranscriptionProviding`, `AudioExtracting`, `RecapProviding` |
| `LibraryViewModel` | `pendingImport`, `urlsHoldingSecurityAccess`, delete/rename candidates | `FreeBookDownloading` (legacy seed catalog) |
| `BrowseLibriVoxViewModel` | search, `syncState`, `activeDownloads`, `featuredBooks`, language/genre/duration filters | `LibriVoxAPIClient`, `LibriVoxCatalogSync` (via SwiftData) |
| `LibriVoxBookDetailViewModel` | `downloadState`, `addToLibraryState`, `isAlreadyInLibrary` | `LibriVoxDownloadService`, `StreamingLibraryService` |
| `StreamedBookDownloadViewModel` | `state` (idle/downloading/done/error) | `LibriVoxDownloadService` |

## Services

Protocol implementations typically `struct`. `LibraryImportService` and catalog/sync services (`LibriVoxAPIClient`, `LibriVoxCatalogSync`, `FreeBookCatalogService`) = `enum` with static methods. `SamplePlayer` + `NetworkMonitor` = singletons.

| Protocol | Implementation | Framework |
|----------|---------------|-----------|
| `TranscriptionProviding` | `TranscriptionService` | Speech |
| `MomentAnalyzing` | `MomentNamingService` (iOS 26+) · `UnavailableMomentAnalyzer` (iOS 18 fallback) | FoundationModels |
| `RecapProviding` | `RecapService` (iOS 26+) · `UnavailableRecapProvider` (iOS 18 fallback) | FoundationModels |
| `AudioExtracting` | `AudioExtractionService` | AVFoundation (AVAssetExportSession) |
| `FreeBookDownloading` | `FreeBookDownloadService` | URLSession (background) — legacy seed catalog |

## AI & On-Device Intelligence

- `MomentNamingService` — moment analysis: name, note, categories, quoteLine, characters, mood. `RecapService` — `RecapGenerationResult` (recap text + optional `progressHeadline`). Both `@available(iOS 26, *)`.
- `TranscriptionService` — Speech framework wrapper bridged with `withCheckedContinuation`.
- `AppleIntelligenceCapability` — runtime detection gating AI UI visibility; iOS-18-safe (internal `if #available(iOS 26, *)` branches). AI is isolated behind protocols; the app works fully without Apple Intelligence.
- `AIEntitlementStore` — StoreKit 2: trial-use tracking + IAP unlock (`AIProductID`). Entitlement state owned entirely by StoreKit (`Transaction.currentEntitlements`).
- **iOS 18 deployment-target rule.** `FoundationModels` is iOS 26-only. Shared types (`MomentAnalysis`, `MomentNamingError`, `RecapError`, `RecapGenerationResult`) live in the protocol files so iOS-18 callers + mocks need no availability gating. ViewModel default inits branch on `if #available(iOS 26, *)` to pick real service vs `Unavailable…` stub. Never reference `FoundationModels` symbols outside an `@available`-gated type or `if #available` block.
- **`SystemLanguageModel.default` has ~4096-token budget shared between input + output.** In `@Generable` structs, order cheap structured fields first, longest prose field last — fields generate in declaration order and the trailing one gets clipped when the budget runs out. Post-process free-text fields for mid-sentence truncation (see `MomentNamingService.trimToCompleteSentences` / `sanitizedQuoteLine`); never trust the model to honor word/sentence-count guides.

### In-App Purchases (two products)

Both StoreKit-owned; the app gates on `Transaction.currentEntitlements` directly — no third-party purchase SDK.

| Product | Store ID | Type | Owner store |
|---------|----------|------|-------------|
| AI Features unlock | `andreibaludev.Pageless.ai_unlock` | Non-consumable | `AIEntitlementStore` |
| iCloud Sync | `andreibaludev.Pageless.icloudsync.monthly` | Auto-renewable monthly ($0.99, **no free trial**) | `ICloudSubscriptionStore.shared` |

- **`ICloudSubscriptionStore`** mirrors `AIEntitlementStore`'s shape (`loadProduct`, `refreshEntitlements`, `purchase`, `restorePurchases`, `Transaction.updates` listener). **Singleton** because `AppDelegate.init` reads `isSubscribedAtLaunch()` (UserDefaults cache) when choosing the SwiftData CloudKit database before SwiftUI env objects exist.
- **No free trial.** `introOfferDisplay` returns nil unless the App Store product actually carries a `.freeTrial` intro offer, so the UI shows "Subscribe" + "$0.99/month". Don't reintroduce a hardcoded trial string.
- **Reachability (Apple 3.1.1).** The iCloud Sync purchase must stay reachable in the reviewed build: Settings → "iCloud Sync" hero card (shown **unconditionally** in `SettingsView.unlockSection`) → `ICloudSettingsView` → "Subscribe" — **not** hidden behind iCloud sign-in. A prior build was rejected under 3.1.1 for this.
- **RevenueCat (removed).** Ran in observer mode for dashboard metrics only; the app never gated on it. SPM package gone, call sites commented out (search `// RevenueCat disabled` in `AppDelegate`, `AIEntitlementStore`, `ICloudSubscriptionStore`). To re-enable: re-add `purchases-ios-spm`, uncomment those blocks, restore RC disclosures in `privacy-policy.md`. Server config still exists (project `proj0c83cb7e`, app `app5156e9dfbb`). End-to-end verification needs TestFlight (local `Products.storekit` receipts can't be validated by RC's backend).

## Feature Systems

### Free Books — two parallel systems (by design)

1. **LibriVox catalog (primary, iPhone)** — 20,000+ books, cached in `LibriVoxBook` via `LibriVoxCatalogSync` (24h incremental sync). UI: "Free Books" tab → `BrowseLibriVoxView` → `LibriVoxBookDetailView`.
   - **Add to Library (streaming)** — `StreamingLibraryService` creates an `Audiobook` with `isDownloaded == false` + remote URLs per `AudioTrack`. No files written; needs network at playback.
   - **Download** — `LibriVoxDownloadService` fetches all tracks; tags `isFreeBook = true`, `catalogId = book.id`, keeps each track's `remoteURLString` so the book shares iCloud identity with a streaming entry and can be matched/re-streamed by id after removal. Also promotes streaming → downloaded (`StreamedBookDownloadViewModel`).
   - **Sample** — `SamplePlayer`, 20s preview. **Network gating** — check `NetworkMonitor.shared.isConnected` before sample play, sync, streaming.
   - **Covers intentionally not fetched** (LibriVox cover URLs unreliable): both services set `coverArtData = nil`; `GeneratedCoverView` renders the letter template. Don't reintroduce remote cover fetches here.
   - **Classics-first load order.** `BrowseLibriVoxViewModel.triggerSyncIfNeeded` awaits `performPreload` (curated `curatedClassicIDs` via `LibriVoxAPIClient.fetchBooks(ids:)` → `LibriVoxCatalogSync.seed`) **before** kicking off the full `performSync`. Blocking overlay (`isInitialLoading`) only while nothing is on screen; afterwards the 20k sync continues behind a non-blocking banner (`isLoadingFullCatalog`). Don't let the full sync run ahead of (or block) the preload.
   - **Hardened API client — never surface raw `DecodingError`.** The feed returns `{"error":"…"}` with HTTP 200 (no match) or HTML (server hiccup); `fetchData` validates status (→ `LibriVoxAPIError.serverUnavailable`), the lenient `decode` helper maps error-envelope/empty to `[]` and unparseable to `.unreadableResponse`. `URLError` deliberately **not** wrapped so `isNetworkUnavailable` offline classification still works. `LibriVoxCatalogSync.fetchPageWithRetry` retries transient page failures (3 attempts, linear backoff).
   - **Offline/empty states** (`BrowseLibriVoxView`): `isOfflineWithNoData` / `isOfflineWithCachedData` / `loadFailedWithNoData`, all featured-aware (cached classics count as "has data").
   - **Collections** — `LibriVoxCollection.all`: hand-curated static shelves (struct + bundled LibriVox project IDs, no backend), horizontal card rail atop `featuredBooksList` → `LibriVoxCollectionView`. `LibriVoxCollectionViewModel.load` resolves local-first from the `LibriVoxBook` cache, fetches only missing IDs via `LibriVoxAPIClient.fetchBooks(ids:)` and seeds through `LibriVoxCatalogSync.seed` (so the full sync dedupes by `id`); curated ID order preserved; offline-with-partial-cache degrades to cached subset. IDs must be verified against the live feed API before adding.

2. **Legacy seed catalog (CarPlay)** — `FreeBookCatalogService`: 5 hand-picked Internet Archive classics, downloaded via `FreeBookDownloadService` (background URLSession; published progress/errors). Consumed only by `CarPlayCoordinator` + `LibraryViewModel`. **Don't extend this path for new iPhone features — use the LibriVox path.**

### Reading Activity & Stats

- `ReadingSession` = only persisted row — one chunk = one book × one wall-clock hour bucket, metadata snapshotted.
- `ReadingSessionRecorder` (`@MainActor`) owned by `AudioPlayerManager`, ticked from its 1s observer while playing. Chunks emit every ~5 min of continuous play; pause / track change / book change / background / finish flush; chunks < 30s dropped as scrub noise.
- `ReadingStats.compute(sessions:booksFinished:)` = pure aggregate → totals, best day/hour/dow, streaks, top author, longest book, free-book share, per-day map. No persistence; recomputed when the sessions `@Query` changes.
- Favorites tab pins `ReadingActivityCard` above the grid (only when `stats.hasAnyActivity`); tap pushes `ReadingStatsView` with a zoom transition out of the card's heatmap. Full view = `ReadingStatsSections` in a `LazyVStack` with `revealOnAppear` + `CountUpText` choreography. `ReadingHeatmap` + `HeatmapPalette` (`.amber`) shared by card + full view.
- `ReadingActivitySeeder` is `#if DEBUG`-only (seeds 113 days of synthetic activity). Never call it from release code paths.

### Equalizer (per-book)

- `EqualizerSettings` — 5 bands (60Hz/250Hz/1kHz/4kHz/14kHz), presets (flat, voiceBoost, bassBoost, trebleBoost, podcast, custom), preamp 0–12 dB, band gain ±12 dB
- `EqualizerTap` — C-level `MTAudioProcessingTap`: biquad filters + soft limiter on the realtime audio thread; coefficients updated under `os_unfair_lock`
- `AudioEqualizerService` (ObservableObject) — live `@Published` state, persists to `Audiobook.equalizerConfiguration`, builds the `AVAudioMix` injected into each `AVPlayerItem`
- `EqualizerSheet` — UI; reads/writes via `@EnvironmentObject AudioEqualizerService`

### Onboarding

Standalone welcome flow, shown once on first launch (and via Settings → "Reset Onboarding"). Replaced the old spotlight walkthrough — no `OnboardingStep` / `SpotlightOverlayView` / `.spotlightTarget()` machinery; don't reintroduce.

- **`OnboardingManager`** — completion gate only: `isComplete` (persisted as `onboardingComplete`), `complete()`, `reset()`. Init migrates legacy users (old `onboardingPhase == 3` counts as complete). `ContentView` presents `OnboardingFlowView` via `.fullScreenCover` while `!isComplete`.
- **`OnboardingFlowView`** — paged vertical `ScrollView` (`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`), six full-screen scenes, right-edge progress-dot rail. The active scene index drives reveal/count-up/stagger animations — `.onAppear` is wrong here (paged rows instantiate before they center).
- **Preference controls bind live to existing `@AppStorage` keys** (`resumeBacktrackSeconds`, `skipBackSeconds`, `skipForwardSeconds`, `momentBacktrackSeconds`) — persistence automatic, scene-6 summary shares one source of truth. "Open Library" calls `complete()` and routes to the chosen home tab. **"Free books" choice persists** via `@AppStorage("startOnFreeBooks")`: when true the app lands on Free Books on **every** launch (one-time `.onAppear` guard in `ContentView` applies it for relaunched users) and tab order becomes Favorites / Free Books / All Books (`tabOrder` computed property drives both `tabPicker` and the swipeable `libraryContent`). "My books" + all legacy users: false — Favorites first, order Favorites / All Books / Free Books.
- **Scenes 4 (Apple Intelligence) and 5 (iCloud Sync) are informational only** — no paywall, no toggles; don't wire purchase/sync state into them.
- **`OnboardingScenes`** = six scenes + widgets (choice cards, `OBRulerPicker`, chip rows, stepper, `OBHeatmap`, moment-naming card, `OBSyncGraphic`, summary). **`OnboardingTheme`** = tokens (`OB.*` colors, `OBMotion`), type primitives (`OBEyebrow`/`OBHeadline`/`OBSub`/`obSerif`), `obReveal`/`obParallax` modifiers.
- **Must render identically on every device/iOS version**: fixed point sizes, fixed 402pt centered content column, `.dynamicTypeSize(.large)` clamp at root (never Dynamic Type), app's own theme via `preferredColorScheme(forceDarkMode ? .dark : nil)`. All animations honor Reduce Motion.

### iCloud Sync (paid feature)

Library metadata, progress, moments, EQ config, reading sessions sync via CloudKit private DB (container `iCloud.andreibaludev.Pageless`). Audio files are **not** synced — re-acquired per device. Gated by the monthly subscription (see In-App Purchases).

- **`IcloudSyncGate`** — single decision point: active subscription (`ICloudSubscriptionStore.isSubscribedAtLaunch()`) AND `iCloudSyncEnabled` UserDefaults toggle AND `FileManager.ubiquityIdentityToken`. If any is false, `AppDelegate` builds the container with `.none` database.
- **Orphan detection** — `OrphanDetectionService` runs at launch and after every `NSPersistentCloudKitContainer.eventChangedNotification` import. A book marked `isDownloaded = true` whose storage folder is absent gets flipped to `isDownloaded = false` (recoverable orphan).
- **Fingerprinting** — `LibraryImportService` computes a SHA-256 fingerprint (first 16 bytes of audio data) per imported track → `AudioTrack.contentFingerprint`. `FingerprintBackfillService` backfills existing tracks on first launch after upgrade.
- **Restore on re-import (own books)** — importing on a new device, `LibraryViewModel` calls `OrphanRestoreService.findMatch` (fingerprint vs orphan candidates). Match → `RestoreMatchSheet` ("Restore from iCloud" / "Add as new"). `adopt` rewrites the orphan's `AudioTrack` records in place, preserving moments/progress/EQ.
- **Match by id (free books)** — free books match on `catalogId`, not fingerprint. Removing a free book with sync on calls `LibraryImportService.archiveFreeBook` (drops files, sets `isArchived = true`, keeps the synced record + remote URLs). Re-adding from the Free Books tab (streaming **or** download) calls `OrphanRestoreService.fetchFreeBackup(catalogId:)`; a hit raises confirmation in `LibriVoxBookDetailView` ("Import from iCloud" reuses the backup in place / "Add as New" creates a fresh copy). If added as new, `AudiobookDetailView`'s iCloud button can still restore via `restoreFreeBackup` (cloud-wins). `isArchived` = the free-book analogue of an own book's `!isDownloaded` orphan state — needed because free `!isDownloaded` alone is ambiguous (active streaming vs removed).
- **`CloudLibraryView`** — the full iCloud Library (every book ever added, so the backup is visibly verifiable), not just orphans. Reachable via Settings → iCloud Library and via the library-header iCloud button (shown only when subscribed; it replaced the old header sort button — sort moved to per-tab chevron menus). Four mutually exclusive buckets: **On this iPhone** (`isDownloaded && !isArchived`), **Streaming** (`!isDownloaded && isFreeBook && !isArchived`, status-only), **In iCloud only** (`!isDownloaded && !isFreeBook`, "Locate…" picker), **Removed free books** (`isArchived && isFreeBook`, "Stream"). Swipe-to-delete on own rows = the **only** permanent cloud-delete path.
- **`ICloudBackupBadge`** — "Backed up to iCloud" affordance (cover overlay + detail inline) whenever `IcloudSyncGate.isEnabled()`. NSPersistentCloudKitContainer has no per-object synced flag, so this is an honest *static* badge (sync on ⇒ synced-store records are backed up), gated so it never promises backup to non-subscribers.
- **Delete copy is subscription-aware** — `ContentView`'s delete dialog branches all six paths (streaming-only / downloaded-free / own × sync-on/off) on `IcloudSyncGate.isEnabled()`. Subscriber own-book delete = single non-destructive **"Remove from this iPhone"** (drops local audio, keeps iCloud backup; deliberately no second local option). Non-subscribers keep the two-option hard delete ("Remove from App" / "Also Delete Files").
- **`isStreamingOnly` tiebreaker** — excludes own-book orphans (`!isDownloaded && !isFreeBook`) so they land in Cloud Library instead of being treated as streaming books.

### CarPlay

- `CarPlaySceneDelegate` → `CarPlayCoordinator` (templates, now-playing, moment saving, legacy seed catalog browsing)
- `CarPlayVoiceSearch` — hands-free dictation (Speech framework), auto-stops on silence
- `VoiceSearchPermissions.primeIfNeeded()` — primes mic + speech permissions at iPhone launch (`PagelessApp.task`) because permission prompts **cannot** appear on the CarPlay screen. Don't add permission requests that can fire only on CarPlay.
- `AppDelegate` — background URL session handler + CarPlay scene registration

### Siri / App Intents

`AudiobookIntents.swift` — `PlayLatestBookIntent` via `UnpagedAppShortcuts` ("Play Latest Book"). The shortcut writes a UserDefaults flag; `PagelessApp` consumes it on `scenePhase == .active`.

## Settings & Preferences

`@AppStorage` keys typed via enums in `PlaybackSettings.swift` (all `CaseIterable, Identifiable`): `LibrarySortOption`, `ResumeBacktrackOption`, `SkipIntervalOption`, `MomentBacktrackOption`, `SleepTimerOption`.

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

Swift Testing (`import Testing`). Run via `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.

- Mocks in `PagelessTests/Mocks/`: `MockTranscriptionService`, `MockMomentAnalyzer`, `MockRecapService`, `MockAudioExtractor`, `MockFreeBookDownloadService` — one per protocol service. LibriVox-path code is tested integration-style against in-memory SwiftData containers; if you add a protocol there, add a matching mock.
- **In-memory test containers: always pass `cloudKitDatabase: .none`** to `ModelConfiguration`. The default `.automatic` picks up the host app's CloudKit entitlement on device and fails CloudKit-shape validation. `SchemaCompatibilityTests.syncedSchemaSatisfiesCloudKitConstraints` is the one intentional `.private(...)` validation, via a file-backed temp store.
- **Hold the container in a local**: `let container = try makeContainer(); let context = container.mainContext` — never `try makeContainer().mainContext` (container deallocates; first fetch crashes the host app).
