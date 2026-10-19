# Playback

Read this before changing `AudioPlayerManager` or anything that reads its state: chapters, the sleep timer, Now Playing, titles and rename, the equalizer, reading sessions and stats, and the rating prompt.

## AudioPlayerManager

- One `AVPlayer` with one `AVPlayerItem` at a time plays local and streaming tracks through the same `load()` path; track navigation is the manager stepping through `Audiobook.sortedTracks`, not an item queue.
- **Load discipline.** Every `await` inside `load()` is followed by an `isCurrentLoad(loadToken)` check before shared state changes, and the item is replaced only after the last `await`. A new `await` there needs the same check, or a stale load overwrites a newer one. Pause invalidates only a load that hasn't committed.
- Each item gets its own `AVAudioMix` from `AudioEqualizerService.makeAudioMix(for:)`; that is how the EQ tap reaches the audio. An asset with no audio track plays without EQ.
- `PlaybackPersistence` owns progress saves, the high-water mark and the seek penalty. It writes model fields on every call but saves only past a delta, so the model can be dirty between saves.
- ABS books reconcile with the server before playback; see `audiobookshelf.md`.

## Chapters

`PlaybackChapter` is computed, never stored or synced. Sources in order: Audiobookshelf book-wide markers mapped onto track offsets, then markers embedded in each file (`EmbeddedChapterReader`, falling back across title locales including `und`), then one chapter per track. A source counts only with at least two usable markers, so a lone marker is dropped silently, and the first chapter always starts at 0. `ChapterListSheet`, the player's previous/next chapter buttons and CarPlay's chapter list all read this one list.

Chapter navigation steps from pending targets: pause invalidates a queued jump, and periodic time readings never overwrite a pending seek until it lands or times out.

Progress math in `Audiobook` compares `orderIndex` with the positional index into `sortedTracks`. Merged iCloud records can carry `orderIndex` ties, where the two diverge.

## Sleep timer

- Minute options store seconds as raw values; `SleepTimerOption.endOfChapter` is the `-1` sentinel.
- End of chapter sets `AVPlayerItem.forwardPlaybackEndTime` from the chapter list, and the end notification is handled before the normal track advance.
- Seeks, chapter rebuilds and track commits retarget the boundary. Manual pause keeps it armed; expiry, Off and book finish clear it.
- Expiry at a file's end stays on that file, and the next Play starts the following file.
- ABS chapters spanning files use book-global end times.
- The DEBUG seconds override (E2E fixture launches only) applies to minute timers.

## Now Playing and remote commands

- `NowPlayingUpdater.update` writes track `displayTitle` → `MPMediaItemPropertyTitle`, the book title alone → `MPMediaItemPropertyAlbumTitle`, author → `MPMediaItemPropertyArtist`.
- Set `MPNowPlayingInfoCenter.default().playbackState` after every `nowPlayingInfo` write: Siri routes pause and resume from it.
- Remote next/previous track commands (AirPods clicks, headphone buttons) map to skip forward/back by the Settings interval, and are disabled when that interval is 0.
- Artwork falls back to `GeneratedCoverView.renderImage(title:side:)`, cached per title.

## Titles and rename

- Playback surfaces show `AudioTrack.displayTitle`. A single-track book's lone track title is file-metadata noise, so `displayTitle` falls back to `Audiobook.title`; multi-track books keep per-track titles. Chapters built per track take their titles from `displayTitle` too, but `chapters` is a stored snapshot rebuilt only on load, track commit and marker refresh: after a rename, the player's and CarPlay's chapter lists show the old title until the next rebuild.
- Rename is display-side: `LibraryViewModel.commitRename` writes `Audiobook.title` only, and `AudioTrack.title` rows stay as imported.
- `MiniPlayerBar` shows the book title and adds a track line only when it differs (`miniSecondaryLine`).

## Equalizer

Per book, persisted in `Audiobook.equalizerConfiguration`. Bands, presets and ranges live in `Models/EqualizerSettings.swift` (`EqualizerBand`, `EqualizerPreset`, `EqualizerConfiguration`).

- `EqualizerTap` is a C-level `MTAudioProcessingTap` (biquads plus a soft limiter) on the realtime audio thread. One heap-allocated state block is shared by every item's mix. The main thread writes coefficients under its `os_unfair_lock`; the audio thread takes the lock only to copy them. Keep the render callback to that pattern.
- `AudioEqualizerService` holds live `@Published` state and builds mixes. Its `persist()` does nothing while no book is bound.
- `EqualizerSheet` binds through `@EnvironmentObject AudioEqualizerService`.

## Reading sessions and stats

- `ReadingSession` is the only persisted stats row: one book in one wall-clock hour, with book metadata snapshotted so stats outlive the book.
- `ReadingSessionRecorder`, owned by `AudioPlayerManager`, is ticked by the player's periodic time observer while playing and credits a fixed amount per tick, so the observer interval and the recorder's crediting change together. It files a chunk under the hour it started, after a stretch of continuous play and on each flush (pause, app resigning active) or `end` (book finished). Chunks under its minimum length are dropped as scrub noise. Thresholds are constants in the recorder. A new way for playback to stop needs a flush there.
- `ReadingStats.compute(sessions:booksFinished:)` is a pure aggregate, computed inline from the sessions `@Query`. Nothing derived is stored.
- The Favorites tab shows `ReadingActivityCard` above the grid once there is any activity, and it zooms into `ReadingStatsView` (sections in `ReadingStatsSections.swift`). `ReadingHeatmapView` and `HeatmapPalette` serve both.
- `ReadingActivitySeeder` generates synthetic history from Settings in DEBUG builds only. Seeding and "Clear Reading Activity" delete every `ReadingSession` row first, real ones included.

## Rating prompt

The app asks for an App Store rating at most once per app version, at a calm, positive moment. The rules are pure functions in `Services/RatingPromptPolicy.swift` (`RatingPromptPolicy.decide`, with `RatingPromptSettling` and the UserDefaults-backed `RatingPromptStore`); `Views/RatingPromptModifier.swift` gathers the inputs and calls the SwiftUI `requestReview` action. Thresholds are constants on the policy, so change them there and in `RatingPromptPolicyTests` together.

- **Positive moment**: a book played to its end within the last 48 hours (`AudioPlayerManager.markCurrentBookFinished` calls `bookFinishedSink`, which stamps the store, so a book finished from CarPlay or a locked phone still counts), or a listening habit read from `ReadingSession` rows (enough total minutes over enough different days, still listening in the last few days).
- **Never**: before the install is two days old (first launch is recorded the first time the phone UI appears), during onboarding, while the scene is not active, over any presented sheet, alert, picker or paywall (the modifier asks UIKit whether the key window's root controller is presenting), while the full player is open, audio is playing or a stream is loading to play (`isPreparingPlayback`), while a CarPlay scene is connected, twice in one `CFBundleShortVersionString`, or within 90 days of the previous request. Apple's own limit (three prompts a year, and it may show nothing) applies on top, and the app cannot tell whether the sheet appeared.
- **Where it can fire**: only from the phone UI. The modifier hangs on `ContentView`, so CarPlay and background launches never reach it.
- **Settling**: the watch polls every two seconds and asks only after two consecutive calm polls, so a sheet that has just dismissed does not trigger it. Any input change restarts the watch.
- **A request is recorded the moment it is made**, so a version is never asked twice even if the system shows nothing.
- E2E hooks (DEBUG fixture launches only) are in `e2e/README.md`: `-e2e-rating-stub` counts requests on screen instead of raising the system sheet.
