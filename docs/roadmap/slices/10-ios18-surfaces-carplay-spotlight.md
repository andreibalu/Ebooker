# Slice 10: iOS 18 Controls, CarPlay Library Search, Spotlight & Settings Polish

## Goal
Bring Unpaged's system integration and Settings up to flagship iOS 18 quality: add Control Center & Lock Screen `ControlWidget`s, make widget Play toggle silently when possible, fix CarPlay voice search to search the user's own library (matching `support.md`) and unify CarPlay moment naming, index books/moments in CoreSpotlight, wire Audiobookshelf downloads into the Dynamic Island Live Activity, and fix Dynamic Type + missing essentials in Settings.

## Verified Current State
- **Missing iOS 18 `ControlWidget`s & foreground-forced widget play:** `PagelessDownloadActivity/DownloadActivityWidget.swift:10-16` exports zero `ControlWidget`s despite targeting iOS 18.0. `PlayLatestBookIntent.swift:14` hardcodes `openAppWhenRun = true`, foregrounding the entire app on every Home Screen widget Play tap. Only 2 App Intents exist (`PlayLatestBookIntent`, `SaveMomentIntent`).
- **CarPlay voice search & moment gaps:** `CarPlayCoordinator.swift:649-693` (`searchFreeBooks`) searches *only* the hardcoded free catalog and `LibriVoxBook`—never the user's active Library or ABS—contradicting `support.md:102` and `store-listing/en-US.md:46`. `CarPlayCoordinator.swift:209-230` names moments `"CarPlay 1"` instead of calling `SaveMomentAction` / `MomentFallbackNamer`. It also ignores `startOnFreeBooks` (`123-145`) and omits thumbnails on library rows (`289-310`).
- **Missing CoreSpotlight, `togglePlayPauseCommand` & ABS Download Live Activity:** Zero `CSSearchableIndex` usage; `NowPlayingUpdater.swift` does not register `togglePlayPauseCommand`; `ABSDownloadManager.swift` does not feed `DownloadLiveActivityController` (only `LibriVoxDownloadRuntime` does).
- **Settings Dynamic Type & missing essentials:** `SettingsDesign.swift`, `SettingsView.swift`, `AISettingsView.swift`, and `ICloudSettingsView.swift` use fixed `.font(.system(size: 11..16))` instead of semantic Dynamic Type styles; `HomeTabRow` (`SettingsView.swift:681-699`) omits `.isSelected` accessibility trait; `SettingsView.aboutSection` (`419-452`) omits app version/build and Support link (despite `support.md:233` promising version at bottom of Settings), Shortcuts discovery (`ShortcutsLink`), Voice Permissions status, and global local storage summary. `LegalURLs.swift:10` points to Apple's generic `stdeula` instead of Unpaged's `/terms/`; `OnboardingScenes.swift:1182` draws iPad/Mac on an iPhone-only app.

## Scope

### 1. iOS 18 `ControlWidget`s & Expanded App Intents
- Add `ControlWidget`s to `PagelessDownloadActivity` (`DownloadActivityWidgetBundle`):
  - **Play / Pause Unpaged** (toggles playback).
  - **Save Moment** (invokes `SaveMomentIntent` silently with `openAppWhenRun = false`).
  - **Sleep Timer** (quick-arms last/default sleep timer or opens timer).
- Update `PlayLatestBookIntent` / add `TogglePlaybackIntent`, `SetSleepTimerIntent`, and `AudiobookEntity` + `PlayAudiobookIntent` (`Pageless/AppIntents/`). Where iOS `AudioPlaybackIntent` runs in-app/background cleanly, avoid forcing foreground launch on widget Play; update `ContinueListeningWidget` to reflect playing state (`Pause` vs `Play`) cleanly.
- Register `togglePlayPauseCommand` in `NowPlayingUpdater.swift`.

### 2. CarPlay Fixes (Library Voice Search, Moment Naming, Tab Order & Artwork)
- Update CarPlay voice search (`CarPlayCoordinator.swift:649-693`) to search **active Library `Audiobook`s first** (by title & author), then connected ABS cache (if configured), then LibriVox/free catalog—making the app match `support.md` and App Store copy.
- Route `saveCarPlayMoment()` through `SaveMomentAction.saveCurrentMoment` so CarPlay bookmarks get real chapter/timestamp labels (`MomentFallbackNamer`) and post `SaveMomentAction.savedNotificationName`.
- Respect `LibraryTab.order` (`startOnFreeBooks`) in CarPlay root tabs, and attach cached cover / `GeneratedCoverView.renderImage` thumbnails to CarPlay library rows.

### 3. CoreSpotlight Indexing & ABS Download Live Activity
- Add `SpotlightIndexingService` (`CoreSpotlight`) indexing active Library `Audiobook`s (title, author, series) and saved `Moment`s (label, quote, notes, book title) on library/moment mutations and startup reconciliation, removing deleted/archived items cleanly.
- Add `unpaged://book/<uuid>` and `unpaged://moment/<uuid>` routes in `UnpagedRoute.swift` and handle `CSSearchableItemActionType` (`onContinueUserActivity`) in `PagelessApp.swift`.
- Wire `ABSDownloadManager` active jobs into `DownloadActivityAggregation` / `DownloadLiveActivityController` so ABS downloads share the same Dynamic Island / Lock Screen Live Activity as LibriVox downloads.

### 4. Settings Dynamic Type, Essentials & Copy Alignment
- Migrate hardcoded `.font(.system(size:))` in `SettingsDesign.swift`, `SettingsView.swift`, `AISettingsView.swift`, and `ICloudSettingsView.swift` to semantic Dynamic Type styles (with appropriate caps for chrome), and add `.accessibilityAddTraits(isOn ? .isSelected : [])` to `HomeTabRow`.
- Add to `SettingsView`:
  - **Shortcuts & Action Button** row (`ShortcutsLink` + brief note about Save Moment / Play Latest Book).
  - **Permissions** status row (Microphone & Speech Recognition, linking to iOS Settings).
  - **Storage** summary row (total downloaded audio footprint across imported, LibriVox, and ABS).
  - **About** footer showing app marketing version + build (`CFBundleShortVersionString (CFBundleVersion)`) and **Support** link.
- Reconcile `LegalURLs.termsOfUse` (verify with owner in Decision Gate whether to keep Apple standard EULA or link `/terms/`) and update `OnboardingScenes.swift` sync graphic from iPhone/iPad/Mac to iPhone-to-iPhone (matching `TARGETED_DEVICE_FAMILY = 1`).

## Decision Gate (Step 3)
**Required.** Run Decision Review on:
1. `AudioPlaybackIntent` in-process vs widget-process execution constraints for `PlayLatestBookIntent` / `TogglePlaybackIntent` (`openAppWhenRun = false` behavior when the app is terminated vs suspended).
2. `LegalURLs.termsOfUse` (Apple `stdeula` vs Unpaged `/terms/` — confirm against App Store Connect EULA configuration before changing!).
3. Spotlight indexing lifecycle & privacy (skip indexing when iCloud/content is sensitive? Ensure zero credentials or private ABS URLs ever enter Spotlight attributes).

## Suggested Layer Split
- **Widgets & Intents:** `PagelessDownloadActivity/*`, `Pageless/AppIntents/*`, `Pageless/Services/ContinueListeningSnapshotWriter.swift`, `Pageless/Downloads/DownloadActivityAggregation.swift`, `Pageless/Downloads/ABSDownloadManager.swift`.
- **CarPlay & Now Playing:** `Pageless/Services/CarPlayCoordinator.swift`, `Pageless/Services/NowPlayingUpdater.swift`.
- **Spotlight & Routing:** `Pageless/Services/SpotlightIndexingService.swift`, `Pageless/App/UnpagedRoute.swift`, `Pageless/App/PagelessApp.swift`.
- **Settings & Onboarding UI:** `Pageless/Views/SettingsDesign.swift`, `Pageless/Views/SettingsView.swift`, `Pageless/Views/AISettingsView.swift`, `Pageless/Views/ICloudSettingsView.swift`, `Pageless/Views/Onboarding/OnboardingScenes.swift`, `Pageless/Utilities/LegalURLs.swift`.
- **E2E & Docs:** `e2e/tests/accessibility-layout.e2e.ts`, `e2e/tests/` (Settings version/Shortcuts/Storage rows, `unpaged://book/<id>` deep link), `docs/ios/system-surfaces.md`, `docs/ios/audiobookshelf.md`, `docs/ios/onboarding.md`, `support.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** `UnpagedRoute` parsing for `unpaged://book/<uuid>` & `unpaged://moment/<uuid>`, `DownloadActivityAggregation` combining LibriVox + ABS jobs, CarPlay voice search ranking (Library before LibriVox), Spotlight attribute builder (verifying no credentials/tokens).
- **E2E & Visual (`verify-ebooker`):** Verify Settings Dynamic Type at accessibility sizes (`accessibility-layout.e2e.ts`), verify version/Support/Shortcuts/Storage rows, verify `unpaged://book/<uuid>` deep link opens the book; explicitly note physical-iPhone-only checks required for CarPlay, Control Center widgets, and background `AudioPlaybackIntent`.
- **Docs:** Update `docs/ios/system-surfaces.md`, `docs/ios/audiobookshelf.md`, `docs/ios/onboarding.md`, and `support.md` (plus `store-listing/en-US.md` draft).
