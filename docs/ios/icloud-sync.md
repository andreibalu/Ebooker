# iCloud sync

Read this before changing anything that syncs, deletes or restores a library record: the sync gate, the CloudKit container, orphan detection, fingerprints, restore on re-import, archived free books, Cloud Library, the backup badge or delete copy.

iCloud sync is a Plus feature (see `purchases.md`). The `"synced"` SwiftData configuration (library, progress, moments, EQ, reading sessions, covers) goes to the CloudKit private database of container `IcloudSyncGate.containerIdentifier`. Audio files never sync; each device re-acquires them.

## The gate

`IcloudSyncGate` is the single decision point: sync-sensitive behavior calls `IcloudSyncGate.isEnabled()` rather than reading the toggle. The one deliberate exception is `ICloudSettingsView`'s caption, which compares the stored preference with the gate to say a change applies after relaunch. It requires the Plus launch cache (`PlusEntitlementStore.isSubscribedAtLaunch()`), the `iCloudSyncEnabled` preference and a signed-in iCloud account (`ubiquityIdentityToken`). It is computed once per process, so a purchase, cancellation or toggle change takes effect after relaunch. When it is false, `AppDelegate` builds the container with `cloudKitDatabase: .none`. DEBUG E2E fixture launches force it off.

## Record states

A book's state comes from flags on `Audiobook`; use its computed properties instead of combining raw flags:

- `isStreamingOnly`: not downloaded, and a free or Audiobookshelf book.
- `isCloudOnlyOrphan`: an own (imported) book whose audio is missing here. Restorable via "Locate…".
- `isArchived`: a free book the user removed while sync was on. The record and remote URLs stay; for a free book, `!isDownloaded` alone can't tell streaming from removed.
- `isInActiveLibrary`: belongs in the grid, CarPlay and Siri on this device.

`_isDownloaded` defaults to true because every row written before the flag existed was downloaded.

## Orphans

`OrphanDetectionService` runs at launch and, while sync is on, after each successful CloudKit import event (`NSPersistentCloudKitContainer.eventChangedNotification`). A downloaded own book whose folder is missing or empty flips to `isDownloaded = false`; files are never deleted. An Audiobookshelf book with any missing track returns to streaming instead.

## Fingerprints

`LibraryImportService.fingerprint` is SHA-256 over the file's head and tail (the whole file when small), its size as little-endian bytes, and its duration in truncated milliseconds; read the function for the exact layout. It is stored per track in `AudioTrack.contentFingerprint`.

- Android's backup restore computes the same digest (`LibraryModels.kt`). Change both together.
- The digest depends on the stored duration and the exact bytes. Changing how duration is measured, stored or rounded, or re-encoding files, silently breaks matching.
- `FingerprintBackfillService` runs every launch and fills tracks with no fingerprint whose files are present.

## Restore on re-import (own books)

- **Import path.** `LibraryViewModel` asks `OrphanRestoreService.findMatch`, which accepts any fingerprint overlap regardless of track count and doesn't check the sync gate. A match shows `RestoreMatchSheet` ("Restore from iCloud" or "Add as new book").
- **Cloud Library "Locate…".** Adopts silently only when the picked files' fingerprints match the book's exactly (`LibraryImportService.hasExactFingerprintMultiset`); any other selection asks the user to confirm replacing the book's audio first.
- **`adopt`.** Updates matched track records in place (by fingerprint, then index), inserts extra incoming tracks and deletes surplus ones. Progress, moments and EQ live on the `Audiobook` and survive. `Moment.trackIndex` is positional, so a changed track count can repoint moments.
- **Merge.** "Match with iCloud" on a book's detail screen (`MatchCloudEntrySheet`) can merge a local book into its cloud record via `OrphanRestoreService.merge`, which deletes the local `Audiobook`.

## Free books

Free books match on `catalogId`, never on fingerprints. `FreeBookIdentityService` resolves downloaded, streaming and archived matches deterministically, and the add, download and legacy CarPlay paths all reuse that row. An archived row reactivates in place, keeping progress, moments, favorites and EQ. A matched free book has no "add as new" path. Removing a free book with sync on calls `LibraryImportService.archiveFreeBook` (drops files, sets `isArchived`, keeps the record and remote URLs).

## Cloud Library

`CloudLibraryView` lists the whole synced library, so the backup is visibly checkable. It is reached from the header Plus button → `PlusHubView` → "iCloud Library" (shown while the gate is on) and from Settings → iCloud Sync → iCloud Library. Each book lands in exactly one bucket:

- **On this iPhone**: `isDownloaded && !isArchived`.
- **Streaming**: `isStreamingOnly && !isArchived`; status only.
- **In iCloud only**: `isCloudOnlyOrphan`, with "Locate…".
- **Removed free books**: `isArchived && isFreeBook`, with "Stream" when a track has a remote URL.

Archived own books have no bucket.

## Deleting synced records

These paths permanently delete a synced record; each needs copy that says so:

- swipe-to-delete in Cloud Library's On this iPhone section (own and downloaded free books);
- "Remove from Library" for an Audiobookshelf book;
- the iCloud merge above;
- the non-subscriber "Remove from App" / "Also Delete Files" options.

`ContentView`'s delete dialog branches by book kind (Audiobookshelf, streaming, downloaded free, own) and, for own books, on `IcloudSyncGate.isEnabled()`. With sync on, an own book gets one non-destructive option, "Remove from this iPhone", which drops local audio and keeps the record; a second local option is left out on purpose.

## Backup badge

`ICloudBackupBadge` ("Backed up to iCloud", as a cover overlay and inline on detail) renders whenever the gate is on. `NSPersistentCloudKitContainer` exposes no per-record sync status, so the badge is a static statement that synced-store records are backed up, gated so it never promises backup to someone without sync.
