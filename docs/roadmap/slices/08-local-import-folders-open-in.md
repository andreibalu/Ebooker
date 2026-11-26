# Slice 08: Frictionless Local Import (Folders, "Open in Unpaged", Track Reordering & Async Copy)

## Goal
Eliminate every major friction point for listeners importing their own M4B/MP3 audiobooks: support selecting entire folders, register "Open in Unpaged" / Share-Sheet handoff from Files/Safari/AirDrop, let users reorder/remove tracks and pick cover art before saving, and move file copying off the main thread with progress feedback.

## Verified Current State
- **Folders rejected:** `Pageless/Views/ContentView.swift:182-188` restricts `.fileImporter` to `[.audio]`, and `LibraryViewModel.swift:47-53` + `LibraryImportService.swift:67-73` explicitly drop directories (`.filter { !$0.hasDirectoryPath }`).
- **No "Open in Unpaged" / document association:** `Info.plist:1-101` declares zero `CFBundleDocumentTypes`, and `PagelessApp.swift:108-116` (`onOpenURL`) only routes `unpaged://` URLs and silently ignores `file://` URLs.
- **Read-only track list:** `ImportAudiobookSheet.swift:70-89` displays tracks in alphabetical filename order with no ability to reorder or remove stray files (and no cover art picker before saving).
- **Main-thread blocking copy:** `ImportAudiobookSheet.swift:122-128` calls `LibraryImportService.importAudiobook` synchronously on `@MainActor` (`LibraryImportService.swift:155-157`), freezing the UI while copying large files.

## Scope

### 1. Folder Import (Recursive Natural Sort)
- Update `.fileImporter` in `ContentView.swift` to allow `[.audio, .folder]` (keeping `allowsMultipleSelection: true`).
- When a selected URL is a directory, hold security-scoped access on the directory URL, recursively enumerate supported audio files (`UTType.audio` conforming extensions, skipping hidden/`__MACOSX`/`.DS_Store` files), sort with natural numeric ordering (`localizedStandardCompare`, respecting nested disc/part folders), and use the folder's display name as fallback `suggestedTitle` when tracks lack a unified embedded `albumName`.
- Ensure every `startAccessingSecurityScopedResource()` on both files and parent directories has a guaranteed matching release in `LibraryViewModel.releaseSecurityScopedAccess()`.

### 2. "Open in Unpaged" (`CFBundleDocumentTypes` + `onOpenURL`)
- Register audio document types in `Info.plist` (`CFBundleDocumentTypes` for `public.audio`, `public.mp3`, `public.mpeg-4-audio`, M4B `com.apple.m4b-audio` / `UTImportedTypeDeclarations` as needed, with `LSHandlerRank = Alternate` and `LSSupportsOpeningDocumentsInPlace = true`).
- Handle incoming `file://` URLs in `PagelessApp.swift` (`onOpenURL`) by forwarding to `LibraryViewModel.handleImportSelection` (with proper security-scoped access), opening `ImportAudiobookSheet` directly on the Library tab—even from cold launch.

### 3. Track Reordering, Exclusion & Cover Picker in `ImportAudiobookSheet`
- Make `ImportAudiobookSheet`'s `Imported Files` section interactive:
  - Drag-to-reorder tracks (`onMove`) and swipe-to-remove stray files (`onDelete`, disabling Save if 0 tracks remain).
  - Update total duration and track count live as tracks are removed.
  - Allow tapping the cover preview (or `GeneratedCoverView` placeholder) to pick & crop a cover photo via existing `PhotosPicker` + `CoverCropView` right inside the import sheet.

### 4. Off-Main-Actor File Staging with Progress
- Make `LibraryImportService.importAudiobook` `async throws`, moving `transaction.stageCopy(from:named:)` file I/O off `@MainActor` (via a detached/background worker using `FileManager` copy with per-track progress callback `(completedTracks, totalTracks)`), while keeping SwiftData model insertion and save on `@MainActor`.
- Show a clean progress indicator in `ImportAudiobookSheet` (`"Importing 3 of 12…"`), disabling dismiss/cancel during final commit while keeping the UI responsive.

## Decision Gate (Step 3)
**Required.** Run Decision Review on:
1. Exact `Info.plist` `CFBundleDocumentTypes` + `UTImportedTypeDeclarations` (for `.m4b` specifically) and `LSSupportsOpeningDocumentsInPlace` copy semantics (Unpaged always copies into `Application Support/Audiobooks/<UUID>/`, never mutates originals).
2. Security-scoped resource lifetime across async background copy + cancellation/error paths.
3. Whether `support.md` / `privacy-policy.md` need updates for folder / Open-In import copy.

## Suggested Layer Split
- **Core / Import:** `Pageless/Services/LibraryImportService.swift`, `Pageless/Services/LibraryMutationTransaction.swift`, `Pageless/ViewModels/LibraryViewModel.swift`, `PagelessTests/` (folder recursion, hidden-file skipping, natural numeric sort, async staging + cleanup on error).
- **System / Routing:** `Info.plist`, `Pageless/App/PagelessApp.swift`, `Pageless/App/UnpagedRoute.swift`.
- **UI:** `Pageless/Views/ImportAudiobookSheet.swift`, `Pageless/Views/ContentView.swift`.
- **E2E & Docs:** `e2e/tests/` (multi-track import with reorder/remove + `-e2e-import` fixture hook compatibility + `openURL` file handoff test), `support.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** Folder expansion with nested discs (`Disc 1/01.mp3`, `Disc 2/01.mp3`, skipping `.DS_Store` & non-audio files), natural numeric sort (`Chapter 2` before `Chapter 10`), folder-name title fallback, async copy staging + rollback on copy failure.
- **E2E & Visual (`verify-ebooker`):** Verify existing `-e2e-import` tests stay green; test reordering/removing tracks in `ImportAudiobookSheet`; verify `xcrun simctl openurl` / file handoff opens `ImportAudiobookSheet`; note physical-device verification needed for AirDrop/Safari Share Sheet.
- **Docs:** Update `support.md` (mention folder import & "Open in Unpaged").
