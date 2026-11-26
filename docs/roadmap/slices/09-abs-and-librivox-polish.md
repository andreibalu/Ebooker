# Slice 09: Audiobookshelf & LibriVox Discovery Polish

## Goal
Upgrade both built-in book sources from "good" to first-class: bring series links, everywhere-visible progress & downloaded badges, sorting, narrator search, and two-way bookmark sync to Audiobookshelf; and bring library-status badges, result sorting, one-tap Clear Filters, and a lightweight Want-to-Listen Wishlist to LibriVox.

## Verified Current State
- **Audiobookshelf gaps:**
  - `AudiobookshelfModels.swift:50-74` does not decode `series` / `seriesName` on `ABSBookMetadata`, so `ABSBookDetailView.swift:67-114` links authors and narrators to `ABSBookGroupView` but never displays the book's series or links to the next book in the series.
  - `ABSBrowseView.swift:274` hardcodes `ABSBookTile(item: item, progress: nil)` for every tile in `All Books` / search, and `ABSBookGroupView.swift:63-75` neither shows progress nor passes `progress` into `ABSBookDetailView`. No on-device downloaded badge appears on ABS tiles, and `ABSBookDetailView.swift:201-239` lacks a "View in Library" button when already added.
  - `ABSBrowseViewModel` hardcodes alphabetical title sort for `All Books`, and local search (`ABSViewModels.swift:345-352`) only checks `title` and `displayAuthor` (ignoring narrator, subtitle, series).
  - Zero ABS bookmark sync (`/api/me/item/:id/bookmark` is unused in `AudiobookshelfClient.swift`).
- **LibriVox gaps:**
  - `BrowseLibriVoxView.swift:633-673` and `LibriVoxBookRow.swift:48-85` do not indicate whether a book is already in Library, downloaded, or finished.
  - `LibriVoxCatalogSync.swift:440-456` hardcodes alphabetical title sort on filtered results—no sort menu (Shortest / Longest / Title / Relevance).
  - Active filter menus (`BrowseLibriVoxView.swift:192-260`) have no one-tap "Clear Filters" chip.
  - No Wishlist / "Save for Later" without adding a streaming book to the active Library grid.

## Scope

### 1. Audiobookshelf Polish
- **Series on Book Detail:** Decode `series` (`id`, `name`, `sequence`) / `seriesName` on `ABSBookMetadata` (handling both array and string shapes from ABS API cleanly). Show clickable Series row/badge in `ABSBookDetailView` navigating via `ABSGroupRoute` to the series screen, and populate `Audiobook.seriesName`/`seriesSequence` on add/download (if Slice 07 is merged).
- **Progress, Downloaded Badges & "View in Library":** Pass `viewModel.progress(for: item)` into `ABSBrowseView` `All Books` tiles and `ABSBookGroupView` rows + detail links. Show a subtle on-device downloaded checkmark/badge on ABS tiles already downloaded locally. Add a **"View in Library"** button on `ABSBookDetailView` when `libraryBook != nil` (matching `LibriVoxBookDetailView`).
- **Browse Sort & Expanded Search:** Add a sort menu on `ABSBrowseView` (`Title`, `Recently Added`, `Author`, `Duration`) and expand local search to match `displayNarrator`, `subtitle`, and `seriesName`.
- **Two-Way ABS Bookmark Sync:**
  - Add `createBookmark`, `updateBookmark`, `deleteBookmark` endpoints in `AudiobookshelfClient` (`/api/me/item/:id/bookmark`, token-safe via existing auth flow).
  - Pull server bookmarks when adding/reconciling an ABS book (deduping by `(absItemID, globalTime)` tolerance so Moments never duplicate), and push newly created/edited/deleted Moments on ABS books (queued/best-effort when offline, never losing local Moments).

### 2. LibriVox Discovery Polish
- **Library-status badges:** Pass a lightweight lookup set (`inLibraryCatalogIDs`, `downloadedCatalogIDs`, `finishedCatalogIDs`) into `BrowseLibriVoxView` and `LibriVoxCollectionView` so rows display a subtle status indicator ("In Library" / downloaded / finished checkmark).
- **Result sorting & one-tap Clear Filters:** Add a sort menu (`Title`, `Shortest`, `Longest`, plus `Relevance` when a search query is active) to `BrowseLibriVoxViewModel` & `LibriVoxCatalogSync` local queries. Show a crisp **"Clear"** pill whenever any filter (`language`, `genre`, `length`) is active.
- **Want-to-Listen Wishlist (Local):** Store saved LibriVox `catalogId`s in a lightweight local store (`@AppStorage` / local SwiftData model in the `"local"` non-synced config, or UserDefaults `[String]` preserving order), with a bookmark button on `LibriVoxBookDetailView` and a compact **"Saved for Later"** section/drawer in `BrowseLibriVoxView`—letting listeners bookmark discoveries without cluttering their active Library.

## Decision Gate (Step 3)
**Required.** Run Decision Review on:
1. ABS bookmark sync conflict/dedup strategy (especially mapping ABS book-global integer seconds ↔ Unpaged `(trackIndex, time)` and handling offline edits/deletes without duplicating Moments across iCloud Sync + ABS).
2. LibriVox Wishlist storage (local-only vs iCloud-synced; confirm zero impact on CloudKit schema if local).
3. Updating `e2e/support/fake-audiobookshelf.ts` to cover series metadata and bookmark endpoints.

## Suggested Layer Split
- **ABS Core & Client:** `Pageless/Models/AudiobookshelfModels.swift`, `Pageless/Services/AudiobookshelfClient.swift`, `Pageless/Services/AudiobookshelfLibraryService.swift`, `Pageless/ViewModels/ABSViewModels.swift`.
- **ABS UI:** `Pageless/Views/Shelves/Audiobookshelf/ABSBrowseView.swift`, `ABSBookDetailView.swift`, `ABSBookGroupView.swift`, `ABSBookTile.swift`.
- **LibriVox Core & UI:** `Pageless/Services/LibriVoxCatalogSync.swift`, `Pageless/ViewModels/BrowseLibriVoxViewModel.swift`, `Pageless/Views/FreeBooks/BrowseLibriVoxView.swift`, `LibriVoxBookDetailView.swift`, `LibriVoxBookRow.swift`, `LibriVoxCollectionView.swift`.
- **E2E & Docs:** `e2e/support/fake-audiobookshelf.ts`, `e2e/tests/audiobookshelf.e2e.ts`, `e2e/tests/free-books.e2e.ts`, `docs/ios/audiobookshelf.md`, `docs/ios/free-books.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** `ABSBookMetadata` series decoding (empty string, array, fractional sequence), ABS global-time ↔ `(trackIndex, time)` bookmark mapping & dedup, LibriVox sort order & filter reset.
- **E2E & Visual (`verify-ebooker`):** Run `e2e/tests/audiobookshelf.e2e.ts` (verify series link on detail, progress badge on All Books, bookmark round-trip against `fake-audiobookshelf`) and `e2e/tests/free-books.e2e.ts` (verify library status badge, duration sort, Clear Filters, Wishlist add/remove across relaunch).
- **Docs:** Update `docs/ios/audiobookshelf.md`, `docs/ios/free-books.md`, and `support.md`.
