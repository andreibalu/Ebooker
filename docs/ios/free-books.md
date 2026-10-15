# Free books (LibriVox)

Read this before changing the Shelves tab's LibriVox source: browse, catalog sync, search, streaming, downloads and their Live Activity, samples, collections, other recordings, or the legacy CarPlay catalog. Views live in `Views/FreeBooks/`.

There are two catalogs:

1. **LibriVox** (primary). The full public catalog, cached locally in `LibriVoxBook`. The Shelves tab (internal `LibraryTab.freeBooks`) shows it through `BrowseLibriVoxView` → `LibriVoxBookDetailView`, and CarPlay search streams from the same cache.
2. **Legacy seed catalog.** A handful of hand-picked Internet Archive classics in `FreeBookCatalogService`, shown only in CarPlay's free-book list. A tap there streams the book (it is added as a streaming row); `FreeBookDownloadService` survives to restore downloads started by older builds and nothing starts new ones. New free-book features build on the LibriVox path.

## Browse design ("Open Shelf")

- Type comes from the 4-size `FBType` scale in `BrowseLibriVoxView.swift` (eyebrow, body, title, headline), which the Audiobookshelf screens share. Book titles and authors are serif (`design: .serif`); metadata uses uppercase `FBEyebrow` labels; the chart rows are numbered.
- Section headers ("Collections", "Popular Classics", …) keep the app's standard voice: `.subheadline.weight(.semibold)`, `.primary`, a hairline rule. They stay that size and style rather than becoming eyebrows.
- Filter labels (language, genre, length) are always `.primary`; the selected one gets a 2pt amber underline instead of a color change.
- The daily hero (`todaysPick`, from `loadTodaysPick`) picks from `curatedClassicIDs` by day of year, from the local cache only. `chartBooks` excludes it so hero and chart never repeat a book.
- **Covers are never fetched.** LibriVox cover URLs are unreliable, so both library services set `coverArtData = nil` and `GeneratedCoverView` draws the title in serif on a palette chosen from the title.

## Catalog sync

- `LibriVoxCatalogSync` runs at most daily. Until one full pass has completed, each run continues a full, resumable pass; after that it syncs incrementally.
- **Classics first.** Before the full sync starts, a preload fetches the curated classics by id (`LibriVoxAPIClient.fetchBooks(ids:)`) and seeds them (`LibriVoxCatalogSync.seed`), so the hero and featured rows work at once. Search and filters stay interactive throughout; a non-blocking banner (`isLoadingFullCatalog`) shows while the full sync runs.
- **Concurrency.** `LibriVoxCatalogStore.make` builds its `@ModelActor` off the main actor; page writes, searches and filter aggregation run on its background context. Commit each page before persisting the next offset in `LibriVoxSyncCheckpoint`, so a crash never skips a page.
- **Lifecycle.** Backgrounding raises a pause flag and uses a short background task to save the current page. Foregrounding resumes from the cursor with exactly one sync in flight.
- Genre backfill completion is tracked separately from partial counts.
- Transient page failures retry inside `fetchPageWithRetry`.

## Search while the catalog fills

- Text and genre queries hit the live feed and merge matching cached rows.
- The feed has no language or duration parameter, so those filters narrow results locally, with a partial-results notice while the cache is incomplete.
- Saved-page updates refresh cached results and filter menus on a throttle, and sync completion reruns the active query locally.
- Genre data needs `extended=1`. Query values must escape `&`, `=` and `+`.

## API client

The feed answers a no-match query with `{"error": …}` and HTTP 200, and a server hiccup with HTML. `LibriVoxAPIClient` never surfaces a raw `DecodingError`: `fetchData` turns a bad status into `LibriVoxAPIError.serverUnavailable`, and the lenient `decode` helper turns an error envelope into `[]` and anything unparseable (including an empty body) into `.unreadableResponse`. `URLError` passes through unwrapped so `isNetworkUnavailable` can still classify offline failures. `fetchBooks(ids:)` drops per-id failures.

## Network gating

Check `NetworkMonitor.shared.isConnected` before sample playback, sync and streaming. It reads true until the path monitor first reports. The offline and empty states (`isOfflineWithNoData`, `isOfflineWithCachedData`, `loadFailedWithNoData` on `BrowseLibriVoxViewModel`) count cached classics as data.

## Add to Library (streaming)

`StreamingLibraryService` creates an `Audiobook` with `isDownloaded == false` and a remote URL on each `AudioTrack`. It writes no files, so playback needs the network.

## Downloads

- One session-wide `LibriVoxDownloadManager`, built by `LibriVoxDownloadRuntime`, owns progress, cancel, retry, failure and completion. Shelves, Library's pinned downloads and the detail screen all show its state; detail screens observe and request work, never own it.
- Transfers run on a background `URLSession` in `LibriVoxBackgroundDownloadCoordinator`, with per-job manifests on disk (`LibriVoxDownloadManifestStore`), so work survives suspension and relaunch. `AppDelegate` routes background-session events to it. The manager's `executor` initializer and `LibriVoxDownloadService.downloadAndImport` are reached only from tests; the coordinator is what ships.
- One track transfers at a time per job. Any track error fails the whole job with no automatic retry; Retry resumes a failed job from the tracks whose files still exist. On relaunch, background tasks with no manifest are cancelled.
- `didFinishDownloadingTo` moves the file synchronously; URLSession deletes it when the callback returns, so a move inside a `Task` loses the file. The system completion handler fires only after queued events drain (`BackgroundEventDrain`).
- `LibriVoxDownloadService.prepareDownload` lists tracks; finishing tags `isFreeBook = true` and `catalogId = book.id`, keeps each track's `remoteURLString`, and promotes an existing streaming or archived row in place.
- `DownloadLiveActivityController` mirrors progress into a Live Activity rendered by the `PagelessDownloadActivity` extension. `DownloadActivityAttributes.swift` is compiled into both targets.

## Identity

Free books dedupe on `catalogId` through `FreeBookIdentityService` (see `icloud-sync.md`). LibriVox rows store the numeric LibriVox id, while legacy catalog rows store seed ids, so the same book added through both paths stays two rows.

## Samples

`SamplePlayer` plays a short preview from a little way into the first track. `LibriVoxSampleButton` (in `LibriVoxBookRow.swift`) is the inline control for rows; the alternatives section has its own. `LibriVoxBookDetailView.fetchSampleURL` resolves the track URL itself (browse view model, then `book.cachedTracks`, then the audiotracks feed), because pushes from the alternatives section arrive with no browse view model.

## Collections

`LibriVoxCollection.all` holds hand-curated shelves as bundled LibriVox ids; there is no backend. They appear as a card rail above the chart and open `LibriVoxCollectionView`. `LibriVoxCollectionViewModel.load` reads the cache first, fetches only missing ids, seeds them so the full sync dedupes by `id`, keeps the curated order, and degrades to the cached subset offline. Verify every new id against the live feed before adding it.

## Other recordings

`LibriVoxAlternativesFinder` groups re-recordings of the same text from the local cache, with no network. The title key strips only known LibriVox suffixes (version numbers, dramatic reading, abridged, unabridged, solo, group, stacked in any combination), then folds case and diacritics. Unknown parentheticals, such as translations, never merge. A match shares `language`, `authorDisplay` and the key, excluding the book itself; the original sorts first, then versions ascending, then other readings.

`LibriVoxAlternativesSection` (version badge, duration, inline sample, push to detail) appears at the bottom of `LibriVoxBookDetailView` and on `AudiobookDetailView` for free books, resolved through `catalogId`. With no alternatives it renders an empty zero-height anchor, so the section keeps its `.task` and its place in the layout.
