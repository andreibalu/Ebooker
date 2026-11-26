# Playback

Read this before changing `AudioPlayerManager` or anything that reads its state: chapters, the sleep timer, Now Playing, titles and rename, the equalizer, reading sessions and stats, and the rating prompt.

## AudioPlayerManager

- One `AVPlayer` with one `AVPlayerItem` at a time plays local and streaming tracks through the same `load()` path; track navigation is the manager stepping through `Audiobook.sortedTracks`, not an item queue.
- **Load discipline.** Every `await` inside `load()` is followed by an `isCurrentLoad(loadToken)` check before shared state changes, and the item is replaced only after the last `await`. A new `await` there needs the same check, or a stale load overwrites a newer one. Pause invalidates only a load that hasn't committed.
- Each item gets its own `AVAudioMix` from `AudioEqualizerService.makeAudioMix(for:)`; that is how the EQ tap reaches the audio. An asset with no audio track plays without EQ.
- `PlaybackPersistence` owns progress saves, the high-water mark and the seek penalty. It writes model fields on every call but saves only past a delta, so the model can be dirty between saves.
- ABS books reconcile with the server before playback; see `audiobookshelf.md`.
- **Playback speed.** CarPlay and Now Playing cycle/advertise `AudioPlayerManager.supportedPlaybackRates`; the phone player exposes finer presets (`playerPresetPlaybackRates`) plus `PlaybackSpeedSheet` for `0.05×` steps across `minPlaybackRate...maxPlaybackRate` (`0.5×–3.0×`). Remaining-time displays on the player, chapter sleep countdown and book detail scale by `1 / playbackRate` (`TimeFormatter.speedAdjustedSeconds`).

## Chapters

`PlaybackChapter` is computed, never stored or synced. Sources in order: Audiobookshelf book-wide markers mapped onto track offsets, then markers embedded in each file (`EmbeddedChapterReader`, falling back across title locales including `und`), then one chapter per track. A source counts only with at least two usable markers, so a lone marker is dropped silently, and the first chapter always starts at 0. `ChapterListSheet`, the player's previous/next chapter buttons and CarPlay's chapter list all read this one list.

Chapter navigation steps from pending targets: pause invalidates a queued jump, and periodic time readings never overwrite a pending seek until it lands or times out.

When the current audio file contains sub-track chapters (`AudioPlayerManager.hasSubTrackChapters`), `PlayerView` shows a toggle between track/file scope (default, persisted in `playerScrubberShowsChapter`) and chapter scope (`currentTrackChapterRange`), letting listeners scrub and read elapsed/remaining time within the current chapter.

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

## Titles, rename and manual progress management

- Playback surfaces show `AudioTrack.displayTitle`. A single-track book's lone track title is file-metadata noise, so `displayTitle` falls back to `Audiobook.title`; multi-track books keep per-track titles. Renaming a book or editing its author (`LibraryViewModel.commitRename` or `AudiobookDetailView`) calls `AudioPlayerManager.refreshMetadataIfCurrent` so the cached chapter list and Now Playing update immediately.
- Rename is display-side: `AudioTrack.title` rows stay as imported.
- `MiniPlayerBar` shows the book title and adds a track line only when it differs (`miniSecondaryLine`).
- **Mark as Finished** (`LibraryViewModel.markFinished`) unloads the book first, then moves position and progress marker to the end of the last track and reports `isFinished: true` for ABS books. It must unload: `PlaybackPersistence.persist` always writes `isFinished = false`, so a book left loaded loses the flag on the next persist (backgrounding, a periodic tick, a pending load). It skips `bookFinishedSink`, so manual cleanup does not trigger the App Store rating prompt.
- The fine-tune speed slider applies the rate live with `setPlaybackRate(_:persist: false)` and persists once when the drag ends, so one gesture makes one SwiftData save and one widget reload.
- **Reset Progress** (`LibraryViewModel.resetProgress`) unloads the book if loaded, clears progress, finished state and stored recap, reports `0` (`isFinished: false`) for ABS books, and preserves saved moments.

## Equalizer

Per book, persisted in `Audiobook.equalizerConfiguration`. Bands, presets and ranges live in `Models/EqualizerSettings.swift` (`EqualizerBand`, `EqualizerPreset`, `EqualizerConfiguration`).

- `EqualizerTap` is a C-level `MTAudioProcessingTap` (biquads plus a soft limiter) on the realtime audio thread. One heap-allocated state block is shared by every item's mix. The main thread writes coefficients under its `os_unfair_lock`; the audio thread takes the lock only to copy them. Keep the render callback to that pattern.
- `AudioEqualizerService` holds live `@Published` state and builds mixes. Its `persist()` does nothing while no book is bound.
- `EqualizerSheet` binds through `@EnvironmentObject AudioEqualizerService`.

## Reading sessions and stats

- `ReadingSession` is the only persisted stats row: one book in one wall-clock hour, with book metadata snapshotted so stats outlive the book.
- `ReadingSessionRecorder`, owned by `AudioPlayerManager`, is ticked by the player's periodic time observer while playing and measures real wall-clock elapsed time between ticks using a monotonic clock, capped per tick so a stall or background gap never credits a lump (the first tick after start or flush credits one second). Old rows recorded before this change remain as stored. It files a chunk under the wall-clock hour it started (so a late-night session starting before midnight counts for its start day), after a stretch of continuous play and on each flush (pause, app resigning active) or `end` (book finished, or a switch to another book: the recorder's own `tick` and, synchronously before the first `await`, `AudioPlayerManager.load()`). A switch must `end`, not flush, because flush keeps the old book active and the new book's chunks would then be filed under it and dropped as noise. Chunks under its minimum length are dropped as scrub noise. Thresholds are constants in the recorder. A new way for playback to stop needs a flush there.
- `ReadingStats.compute(sessions:booksFinished:today:calendar:)` is a pure aggregate computed inline from the sessions `@Query` without trusting input order; nothing derived is stored.
  - **Session coalescing:** Rows with a usable `createdAt` (not `distantPast` and whose estimated start lies within the recorder's bucket tolerance) are sorted by `(createdAt, id)` and merged into the same logical session when they belong to the same `bookID` and arrive within the coalescing gap tolerance of the chunk's duration (which also accommodates older book-time rows across playback speeds). Rows without a usable `createdAt` are sorted by day, then book, then hour, so another book's row in the same hour cannot split a book's run, and join the previous row when it is the same book on the same day in the same or the next hour. The bucket instant that decides "usable" sets the wall-clock hour on `date` with `calendar.date(bySettingHour:minute:second:of:)` (checking both the first and `.last` occurrence on a fall-back day), never `Calendar.date(byAdding:)` or `hour * 3600` seconds, both of which add elapsed time and land an hour off on DST days. Timed and untimed rows never merge with each other.
  - Coalescing needs no stored session id on purpose: a synced id would need a CloudKit schema change, would cover only new rows, and older app versions on another device would keep writing rows without it.
  - **Streak grace:** `currentStreak` counts backwards from `today` if `today` has activity, or from `yesterday` if `today` has none yet (`isStreakActiveToday` distinguishes the two for UI copy), and is unbounded by `daysTracked`. A `dayKey` ahead of `today` (timezone travel west) counts as `today`.
  - **Top books and daily breakdown:** `topBooks` and per-day `topBookTitle` sort by minutes descending, then title, then `id.uuidString`.
- `ReadingStatsScreen` owns the SwiftData queries, `today` state (refreshed on `.NSCalendarDayChanged` and `UIApplication.significantTimeChangeNotification`), and device-local `@AppStorage` preferences (`dailyListeningGoalMinutes` and `readingHeatmapPalette`), serving both the Favorites `ReadingActivityCard` zoom destination (`backLabel: "Library"`) and **Settings → Reading Activity** (`backLabel: "Settings"`).
- The Favorites card is a plain-style `Button`, so VoiceOver and `library.e2e.ts` read its text as one element. `ReadingStatsScreen` counts finished books with `fetchCount` (a filtered `@Query` there re-rendered in a loop), so that count refreshes only when the screen re-renders. Its hero heatmap scales cells down to fit the column, which must hold at Display Zoom's 320 pt width (`StatsHeroGeometryTests`).
- Daily goal progress reads `todayMinutes`, so it can lag live playback by up to one unflushed chunk.
- The shareable summary card in `ReadingStatsView` renders lazily on share via `ImageRenderer` and intentionally omits book titles and authors.
- `ReadingActivitySeeder` (and `E2EFixtures.realisticCreatedAt`) generates synthetic history from Settings in DEBUG builds only, setting realistic `createdAt` timestamps via `calendar.date(bySettingHour:minute:second:of:)` so DST days keep their wall-clock hour instead of shifting by an hour as `Calendar.date(byAdding:)` does. Seeding and "Clear Reading Activity" delete every `ReadingSession` row first, real ones included.

## Rating prompt

The app asks for an App Store rating at most once per app version, at a calm, positive moment. The rules are pure functions in `Services/RatingPromptPolicy.swift` (`RatingPromptPolicy.decide`, with `RatingPromptSettling` and the UserDefaults-backed `RatingPromptStore`); `Views/RatingPromptModifier.swift` gathers the inputs and calls the SwiftUI `requestReview` action. Thresholds are constants on the policy, so change them there and in `RatingPromptPolicyTests` together.

- **Positive moment**: a book played to its end within the last 48 hours (`AudioPlayerManager.markCurrentBookFinished` calls `bookFinishedSink`, which stamps the store, so a book finished from CarPlay or a locked phone still counts), or a listening habit read from `ReadingSession` rows of the last `habitWindow` (enough minutes over enough different days, still listening in the last few days). The fetch carries a date predicate, so older history is never loaded.
- **Never**: before the first launch recorded by this feature is two days old (the clock starts the first time the phone UI appears, so existing users start it on their first launch after updating), during onboarding, while the scene is not active, over any presented sheet, alert, picker or paywall (the modifier asks UIKit whether the key window's root controller is presenting), while the full player is open, audio is playing, a stream is loading to play (`isPreparingPlayback`) or an Audiobookshelf resume is waiting on its server (`isAwaitingServerResume`), the keyboard is up, while a CarPlay scene is connected, twice in one `CFBundleShortVersionString`, or within 90 days of the previous request. Apple's own limit (three prompts a year, and it may show nothing) applies on top, and the app cannot tell whether the sheet appeared.
- **Where it can fire**: only from the phone UI. The modifier hangs on `ContentView`, so CarPlay and background launches never reach it.
- **Settling**: the watch polls every two seconds while a moment exists (every 30 s while it waits for one, since a play, pause or finish restarts it) and asks only after two consecutive calm polls, so a sheet that has just dismissed does not trigger it. Any input change restarts the watch.
- **A request is recorded the moment it is made**, so a version is never asked twice even if the system shows nothing.
- E2E hooks (DEBUG fixture launches only) are in `e2e/README.md`: `-e2e-rating-stub` counts requests on screen instead of raising the system sheet.
