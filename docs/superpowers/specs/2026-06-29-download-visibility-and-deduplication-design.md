# Download Visibility and Deduplication Design

## Goal

Keep LibriVox download status visible across navigation and app backgrounding while the app process remains alive, expose active downloads in Library, prevent future duplicate free-book and imported-book entries, and rename visible "All Books" copy to "Library".

Force-quit and relaunch recovery is outside scope. Existing duplicate rows remain unchanged.

## Download Architecture

Add one `@MainActor @Observable` session-wide LibriVox download manager and inject it through the SwiftUI environment. The manager owns each download task and its complete UI state, keyed by LibriVox `catalogId`. Detail ViewModels may request work, but they do not own task lifetime or authoritative progress.

Each download entry records:

- LibriVox catalog ID and book metadata needed before an `Audiobook` exists
- Optional `Audiobook` identity for streaming-to-downloaded promotion or iCloud restore
- Phase: preparing tracks, downloading, cancelling, failed, or complete
- Completed and total track counts
- Retry context and cancellation task

Registration happens before track discovery. This closes the current gap where leaving during track lookup loses all visible status. A second request for an active catalog ID observes the existing entry and never starts another task.

Successful completion updates SwiftData first, then removes transient manager state. Confirmed cancellation removes state after task cleanup. Failure remains visible until retry or dismissal so navigation cannot erase useful error information.

The manager supports both primary paths:

1. Fresh catalog download: download tracks, then create one downloaded `Audiobook`.
2. Existing streaming or archived free book: download into the existing `Audiobook` in place, preserving progress, moments, EQ, and iCloud identity.

The manager remains in memory when navigation changes or the app backgrounds. No persistence or background-session reconstruction is added for force-quit recovery.

## Download UI

Free Books and Library read the same manager state.

- Free Books keeps a pinned active-download section independent of search, filter, empty, offline, or collection state.
- Library shows a pinned "Downloading" section above its grid. Fresh catalog downloads appear there before an `Audiobook` row exists. Streaming promotions and iCloud restores appear there while their existing library row remains visible.
- Existing book cards receive matching download state by `catalogId`. While promotion is active, cards show download progress instead of misleading streaming status.
- Every LibriVox detail route, including alternatives and Library audiobook details, reads manager state. Re-entry shows preparing, progress, cancellation, failure/retry, or completion consistently.
- Favorites does not duplicate the pinned download section; Library is the canonical global download surface.

Progress remains track-based because the current service reports completed tracks, not byte progress within a track.

## Free-Book Deduplication

LibriVox project `catalogId` is authoritative identity. Title and author are not identity because alternate recordings must remain distinct.

Add app-level lookup and defensive service checks because synced SwiftData models cannot use `@Attribute(.unique)` under CloudKit constraints.

Behavior for an Add or Download request:

- Active or queued download with same `catalogId`: observe existing manager entry.
- Existing downloaded book: return or open existing row; create nothing.
- Existing streaming book: Add returns existing row; Download promotes existing row in place.
- Existing archived iCloud book: restore and reuse existing row. Remove the "Add as New" path that could deliberately create a duplicate.
- No existing row: create one book through normal path.

Service-level checks repeat identity validation immediately before insertion to prevent alternate callers or concurrent UI routes from bypassing ViewModel checks.

Legacy CarPlay free-book queue also rejects IDs already active, queued, or persisted, and finalization performs a defensive catalog-ID lookup before inserting.

## Imported-Book Deduplication

Use fingerprints already computed by `LibraryImportService.prepareImport`. A pending own-book import is a duplicate only when an active own book has the exact same fingerprint multiset:

- Same track count
- Every pending track has a non-nil fingerprint
- Existing book has the same fingerprints with the same occurrence counts

This catches renamed or moved copies of identical files. Partial overlap remains allowed, preventing false positives for books sharing an intro or chapter. Re-encoded audio may have different fingerprints and remains allowed. Title and author alone never block import.

Check after import preparation and before presenting the metadata sheet. If duplicate, show an "Already in Library" alert and release all security-scoped URLs. Repeat the exact check inside `LibraryImportService.importAudiobook` before copying files or inserting models to protect against races and direct callers.

Orphan iCloud restoration keeps its existing specialized flow. Active duplicate detection does not delete, merge, or repair rows already present.

## Naming

Rename user-visible "All Books" copy to "Library" in:

- Main library tab
- Settings launch-tab preference
- CarPlay library tab
- Onboarding or accessibility copy that names the tab

Keep internal symbols and stored preference keys such as `.allBooks`, `allBooksSortRaw`, and `librarySortOption` unchanged to avoid unnecessary migrations.

## Error and Cancellation Behavior

- Network or service failure remains in shared state with retry and dismiss actions.
- Retry reuses catalog identity and cannot create a parallel task.
- Cancellation enters a cancelling phase, cancels the owned task, waits for service cleanup, then removes state.
- Detail navigation never cancels a download.
- App backgrounding never cancels a download explicitly; normal OS suspension rules still apply.
- Partial files continue using current service cleanup behavior.

## Tests and Verification

Use test-driven development for every production change.

Add focused tests for:

- Registration before track preparation
- State survival when screen-local ViewModels are recreated
- Fresh and streaming download progress
- Duplicate active-start rejection
- Cancellation cleanup and immediate-restart safety
- Failure persistence, retry, and dismissal
- Completion after SwiftData update
- Free-book add/download behavior for active, downloaded, streaming, and archived matches
- Alternative-detail and legacy CarPlay duplicate guards
- Exact imported fingerprint-multiset rejection
- Renamed/moved identical-file rejection
- Partial-overlap allowance
- Nil-fingerprint allowance
- Defensive service-level race checks
- Visible label mapping from "All Books" to "Library"

Run XcodeBuildMCP in this order:

1. `mcp__XcodeBuildMCP__session_show_defaults`
2. `mcp__XcodeBuildMCP__test_device` with scheme `Pageless`, device `00008130-000471A80C81001C`, and `extraArgs: ["-parallel-testing-enabled", "NO"]`
3. `mcp__XcodeBuildMCP__build_device`

No external packages or external-facing documentation changes are required.
