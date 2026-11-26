# Slice 07: Library Book Search, Filters & Series/Shelves

## Goal
Make large libraries effortless to navigate: add real book search alongside Moment search, add Status / Offline-Ready / Source filters (including Hide Finished) and sort direction, and add CloudKit-safe Series metadata + lightweight Custom Shelves / "Up Next" organization.

## Verified Current State
- **No Library book search:** The header magnifying glass (`Pageless/Views/ContentView.swift:504-511`) opens `MomentSearchView` only. There is no way to search `Library` or `Favorites` by book title or author.
- **No Library filtering:** `displayedBooks(for:)` (`ContentView.swift:1016-1041`) has zero filters—finished books stay mixed into the Library grid forever, and listeners cannot filter to **Downloaded (Offline Ready)** books before a flight or by source.
- **Fixed sort direction & hidden sort control:** `LibrarySortOption` (`PlaybackSettings.swift:8-31`) supports 5 fixed-direction sorts opened only by tapping the already-selected tab title.
- **Flat organization:** `Audiobook.swift` has only `isFavorite`—no series name/sequence (even ABS series metadata is discarded on add) and no custom shelves/collections or Up Next queue.

## Scope

### 1. Unified Search (Books + Moments)
- Upgrade the header magnifying glass sheet (or add a clean segmented scope `Books | Moments` inside the search sheet, defaulting to `Books` or remembering last scope while preserving `MomentSearchView` identifiers/behavior when `Moments` is selected):
  - **Books scope:** Instant in-memory folded substring search across active books' `title`, `author`, `seriesName`, and `shelfNames`, showing cover, title, author, progress/finished pill, downloaded/streaming indicator, and tapping straight into `AudiobookDetailView` (with a quick Play button).
  - **Moments scope:** Full existing `MomentSearchView` experience (plus transcript search from Slice 02).

### 2. Library Filters & Sort Polish
- Add a compact, horizontally scrollable filter bar (extending cleanly to the screen edge per `AGENTS.md` → *Large text and Button Shapes*) or filter menu on the Library tab:
  - **Status:** `All`, `In Progress`, `Not Started`, `Finished`, plus a quick **"Hide Finished"** toggle (`@AppStorage("libraryHideFinished")`).
  - **Availability:** `All`, `Downloaded` (offline-ready), `Streaming`.
  - **Source:** `All`, `My Files`, `LibriVox`, `Audiobookshelf` (shown only when the user actually has books from >1 source).
  - **Sort:** Keep existing 5 sort options, add `Remaining Time`, and allow ascending/descending direction toggle + visible sort button (while keeping re-tap on tab title working).
- Show a clear empty-filter state with a one-tap **"Clear Filters"** button when filters hide all books.

### 3. Series Metadata & Custom Shelves (CloudKit-Safe)
- Add optional private backing fields on `Audiobook` (`Pageless/Models/Audiobook.swift`):
  - `_seriesName: String?` (computed `seriesName: String?`)
  - `_seriesSequence: String?` (computed `seriesSequence: String?`, supporting numeric/fractional sorting like `"1"`, `"2.5"`)
  - `_shelfNamesRaw: String?` (JSON `[String]` computed `shelfNames: [String]`, matching `Moment.categories` / `Moment.characters` so no new CloudKit join table is needed and merges stay conflict-free!)
- Auto-populate `seriesName`/`seriesSequence` when adding/downloading an ABS book (once Slice 09 or this slice decodes ABS series metadata).
- Allow editing `Series` & `Book #` in Edit Book Details (`AudiobookDetailView` / `ContentView`), and assigning/creating lightweight **Shelves** (including a built-in **"Up Next"** shelf) from the book context menu and detail screen, with a shelf filter pill in the Library filter bar.

## Decision Gate (Step 3)
**Required.** Run Decision Review on:
1. CloudKit schema shape: JSON-backed `_shelfNamesRaw` on `Audiobook` vs a separate `@Model Shelf` relationship (verify CloudKit merge & orphan/archive behavior and `SchemaCompatibilityTests`).
2. Unified search UX (`Books | Moments` segmented sheet vs inline `.searchable` on `ContentView`) and impact on existing `momentSearchButton` E2E tests and 320pt Display Zoom header width.

## Suggested Layer Split
- **Core / Models:** `Pageless/Models/Audiobook.swift`, `Pageless/Models/PlaybackSettings.swift`, `Pageless/ViewModels/LibraryViewModel.swift`, `PagelessTests/SchemaCompatibilityTests.swift` + pure filter/sort/series-order unit tests.
- **UI:** `Pageless/Views/ContentView.swift`, `Pageless/Views/LibrarySearchView.swift` (or updated `MomentSearchView.swift`), `Pageless/Views/AudiobookDetailView.swift`, `Pageless/Views/ShelfPickerSheet.swift`.
- **E2E & Docs:** `e2e/tests/library.e2e.ts`, `e2e/tests/accessibility-layout.e2e.ts`, `docs/ios/icloud-sync.md` (schema note), `support.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** `SchemaCompatibilityTests` (mandatory for synced `Audiobook` additions!), plus pure tests for numeric/fractional series sorting, book search folding, and combined status/downloaded/shelf filters.
- **E2E & Visual (`verify-ebooker`):** Test searching books by title/author, filtering Hide Finished / Downloaded, assigning a book to a custom shelf, editing series, and running `e2e/tests/accessibility-layout.e2e.ts` to verify header & filter row at accessibility text sizes + Button Shapes + 320pt width.
- **Docs:** Update `docs/ios/icloud-sync.md` and `support.md`.
