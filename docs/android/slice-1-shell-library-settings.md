# Slice 1: app shell, local library, settings and schema v2

Implemented under the 2026-10-06 parity brief. The current single `app` module
and `LibraryStore` interface remain; no Room, cloud backend or purchases were
added. Playback will use AndroidX Media3 ExoPlayer and MediaSessionService.
Android UI reads the latest iOS source in the main checkout as a spec.
Only `android/` and `docs/android/` change. No tracker writes or push.

## Persistence contract for subsequent slices

`SQLiteLibraryStore` opens `library.db` at version **2**. Upgrade is additive:
all v1 book/track rows, IDs, titles, filenames, durations and fingerprints stay.
Explicit ALTER statements add favorite, nullable last-played epoch milliseconds,
track index, position/high-water milliseconds, speed (1.0), finished/free flags,
nullable catalog ID, downloaded (true), owned storage bytes, nullable EQ JSON,
and date-added epoch milliseconds. Since v1 stored no date, its rowid supplies
an ordered fallback date; new imports use the wall clock. Migration measures
existing owned UUID audio folders for storage size and never deletes files.

Track `title` already existed in v1. Nullable `remote_url` is added; a streaming
track uses `storedName = ""`, a remote URL and `isDownloaded = false`. Empty
stored names must never be resolved into a local playback file. This retains
v1's NOT NULL local filename column without destructive table replacement.

`moments` contains id, book FK, track index, timestamp, label, notes, categories
JSON, nullable quote, characters JSON, nullable mood and created-at. Its FK
cascades with the book; `(book_id, created_at)` is indexed. `saveMoment` inserts
or updates atomically without REPLACE semantics. All database calls belong on
an IO worker. Repository APIs expose toggle favorite, progress update, list/save/
delete moments. Progress writes reject negative indices/times and invalid speed;
high-water is monotonic for later playback tracking. The displayed progress and
remaining time use the current book-global position, matching iOS even after a
backward seek.

`UnpagedPreferences` is the single small SharedPreferences wrapper; no DataStore
was present. Keys mirror iOS: `librarySortOption`, `favoritesSortOption`,
`startOnFreeBooks`, `resumeBacktrackSeconds`, `momentBacktrackSeconds`,
`skipBackSeconds`, `skipForwardSeconds`, `appAppearance`. The placeholder Shelves
sort uses `shelvesSortOption`. Sort defaults to Recently Played independently
per tab. Resume defaults to 60s, moment offset to 0s, skips to 30s, appearance
to system. Default landing is Favorites; Shelves is the alternate Open To
preference. Changing preferences observes the same owner and recolors every
Compose app surface immediately, including import review.

## UI and next-slice boundaries

Header/count badge, settings/add buttons, underline tabs and horizontal pager,
favorite grid/empty states, heart overlays, ordered per-tab sorting, storage and
progress card metadata, last-played badge and long-press Delete now exist.
Delete opens the iOS local-book dialog title/body with Cancel and **Also Delete
Files**; the operation removes the index and owned private audio while preserving
provider originals. The separate iOS **Remove from App** option (retain owned
audio) is not implemented and is not offered.

Detail has a circular back button, centered title, header/progress card,
Play/Continue pill, moments and ordered tracks disclosures. `DetailTopBar`
accepts a nullable Player callback (hidden when absent). `BookDetails` accepts
nullable Play/track callbacks: the current shell disables those controls until
the Media3 playback slice supplies them. There is no fake playback or old
"Playback unavailable" message. Moments can be read/rendered; creation/editing
UI belongs to the moments slice. Shelves is a separate minimal placeholder.

Settings opens as a medium-height scrollable modal sheet and expands upward,
with Done, Playback option trays, Open To,
Appearance and the iOS About legal links. The iOS Support section contains only
the excluded coffee purchase, so no empty Support header is rendered. Sources,
Reset Onboarding, Plus, iCloud and AI purchases are omitted. Legal destinations
currently match iOS exactly, including its Apple standard EULA; Android legal
terms and policy applicability need release qualification before publication.

Theme colors/radii/shadows live in `UnpagedTheme.kt`, with the stable iOS cover
palette kept in `LibraryPresentation.kt`. Material icons and Android serif/
Roboto are substitutes for SF Symbols/New York/San Francisco. The appearance
subtitle says "phone" rather than "iPhone". The supplied dark-detail reference
is a duplicate Library capture; matching dark-detail screenshot comparison is
unavailable (see evidence). The library's
case-insensitive sort is not full Foundation locale collation. Android system
bars and Material sheet behavior differ. Cover replacement, reading activity,
network sources, playback/mini player, onboarding and moment creation are later
slices. Payments and Apple sync remain excluded.

## Validation

See the slice 1 section in [E2E evidence](e2e-visual-validation-2026-10-06.md)
for executed commands, counts and capture/report locations. Fixtures go through
the real document picker; no production test hooks or DB-based E2E assertions.
Robolectric covers the actual v1→v2 SQLite upgrade/reopen, all persisted fields,
progress/favorite updates, moment create/edit/delete/FK cascade and rollback.
