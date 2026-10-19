# iCloud sync

Read this before changing anything that syncs, deletes or restores a library record: the sync gate, the CloudKit container, orphan detection, fingerprints, restore on re-import, archived free books, Cloud Library, audio in iCloud, the backup badge or delete copy.

iCloud sync is free for anyone signed in to iCloud; it is not part of Plus (see `purchases.md`). The `"synced"` SwiftData configuration (library, progress, moments, EQ, reading sessions, covers) goes to the CloudKit private database of container `IcloudSyncGate.containerIdentifier`. Audio files sync only when the user stores them in iCloud (see "Audio in iCloud"); otherwise each device re-acquires them.

## The gate

`IcloudSyncGate` is the single decision point: sync-sensitive behavior calls `IcloudSyncGate.isEnabled()` rather than reading the toggle. The deliberate exceptions are the captions in `ICloudSettingsView`, the Settings root and the onboarding iCloud scene, which compare the stored preference with the gate to say a change applies after relaunch. The gate requires the `iCloudSyncEnabled` preference and a signed-in iCloud account (`ubiquityIdentityToken`). It is computed once per process, so a toggle change takes effect after relaunch: the SwiftData container can't switch databases while it runs. When it is false, `AppDelegate` builds the container with `cloudKitDatabase: .none`.

- **Opt-in.** The preference defaults to off. It is offered in Settings → iCloud Sync and on the onboarding iCloud scene, both bound to the same key. Turning sync on silently for existing users would start uploading covers and change what Remove does (archive and keep instead of delete), so nobody gets it without asking.
- **Upgrading from Plus-gated sync.** Plus used to be a second condition. The preference key and its meaning didn't change, so a subscriber with sync on keeps syncing through the update. Someone whose Plus lapsed while the toggle was on gets sync back on the first launch after the update, because that was their last choice and the old screen hid the toggle from them.
- **Fixtures.** DEBUG E2E fixture launches always build the local store. In them `hasUbiquityIdentity()` answers `-e2e-icloud-account` instead of the real account, so the gate, its relaunch rule and every sync-on surface run without CloudKit.

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

`CloudLibraryView` lists the whole synced library, so the backup is visibly checkable. It is reached from the Settings root's iCloud section ("iCloud Library", shown while the gate is on) and from Settings → iCloud Sync → iCloud Library. Each book lands in exactly one bucket:

- **On this iPhone**: `isDownloaded && !isArchived`. Own books add a line saying where their audio is.
- **Streaming**: `isStreamingOnly && !isArchived`; status only.
- **In iCloud only**: `isCloudOnlyOrphan`. "Download" when `CloudAudioStore` reports its audio `.stored`, otherwise "Locate…". Locate… stays in the row's context menu either way.
- **Removed free books**: `isArchived && isFreeBook`, with "Stream" when a track has a remote URL.

Archived own books have no bucket.

## Deleting synced records

These paths permanently delete a synced record; each needs copy that says so:

- swipe-to-delete in Cloud Library's On this iPhone and In iCloud only sections;
- "Remove from Library" for an Audiobookshelf book;
- the iCloud merge above;
- the sync-off "Remove from App" / "Also Delete Files" options.

With sync on, deleting a record deletes it on every device, so its audio in iCloud goes too (`CloudAudioStore.bookDeleted`), and the Cloud Library dialog names the audio when there is some. With sync off the record still exists in iCloud for other devices, so a local delete never touches cloud audio.

`ContentView`'s delete dialog branches by book kind (Audiobookshelf, streaming, downloaded free, own) and, for own books, on `IcloudSyncGate.isEnabled()`. With sync on, an own book gets one non-destructive option, "Remove from this iPhone", which drops local audio and keeps the record; a second local option is left out on purpose. Its message says whether the audio stays in iCloud, from the book's `CloudAudioState`.

## Backup badge

`ICloudBackupBadge` ("Backed up to iCloud", as a cover overlay and inline on detail) renders whenever the gate is on. `NSPersistentCloudKitContainer` exposes no per-record sync status, so the badge is a static statement that synced-store records are backed up, gated so it never promises backup to someone without sync.

## Audio in iCloud

`CloudAudioStore` keeps optional copies of own (imported) books' audio in the app's iCloud Drive ubiquity container, in `<container>/Audiobooks/<folderName>/<storedFileName>`, which mirrors local storage under the book's synced `folderName`. Another device, or this one after a reinstall, downloads the book from Cloud Library instead of locating the file again.

- **Why iCloud Drive and not CloudKit assets.** The system daemon uploads and downloads in the background, resumes and retries, follows the user's iCloud Drive cellular setting, and reports per-file progress through `NSMetadataQuery`. CKAsset records would need a custom zone, schema deployment to the production CloudKit environment, our own long-lived operations and retry, and whole-file transfers. Both count against the same iCloud quota. The cost is that iCloud Drive must be on for the account and for Unpaged; `CloudAudioStore.availability` reports `.driveUnavailable` otherwise.
- **Capability.** The entitlements add `CloudDocuments` and `com.apple.developer.ubiquity-container-identifiers` for the existing container. The App ID's iCloud capability (`XCODE_6`) and its profiles already grant both, so the developer portal needed no change.
- **No extra local space.** `ICloudDriveAudioBackend.copyIn` clones the file into tmp and hands the clone to iCloud with `setUbiquitous`. APFS clones share blocks, so the cloud copy costs nothing locally until one side changes. The folder sits outside `Documents`, so the Files app doesn't show it.
- **Needs sync.** The store is active only while the gate is on this launch, because the synced record is what tells another device the book exists.
- **Own books only.** Free LibriVox books and Audiobookshelf books download again from their source, so copying them would spend the user's quota for nothing. `CloudAudioStore.isEligible` excludes them.
- **The choice.** `iCloudAudioEnabled` is per device and defaults to off: one iPhone may hold books too large for the account's quota. On, it stores each new import and each book whose audio this device replaces. Turning it on offers to store every book already here, with the estimated size; turning it off offers to remove all audio from iCloud, warning about books this iPhone doesn't have. The detail screen's `CloudAudioBookCard` stores or removes one book regardless of the setting.
- **What "stored" means.** `CloudAudioState.derive` is `.stored` only when every track's file is in the folder and fully uploaded. Download, the delete copy and "the audio stays in iCloud" all depend on that, so a file still uploading or missing must never count. `CloudAudioStateTests` hold the rules.
- **Never overwrite or delete on resume.** At the first report each launch, a book with a partial cloud folder and local files gets its missing files copied in. Resuming never overwrites or deletes, since another device may be uploading a newer copy right now. Only the device that replaces a book's audio (Locate…, restore on import, merge) clears and re-uploads the folder (`bookAudioReplaced`). Two devices storing the same file make an iCloud Drive conflict; the copies are identical, so the monitor keeps the current version.
- **Remove from this iPhone** keeps the cloud copy and evicts this device's downloaded copy of it, or the clone would keep the space the user meant to free. Files still uploading can't be evicted; launch maintenance evicts them later for books that are no longer downloaded here.
- **Download** asks iCloud for each file, tracks progress from the metadata, then moves the files into local storage through a `LibraryMutationTransaction` and sets `isDownloaded`. The track records already describe the files, so nothing else changes.
- **No sweep of folders without a book.** A new device's CloudKit import arrives in batches, so a folder whose record hasn't arrived yet looks orphaned. Folders left behind by a record deleted on an older app version stay until the user turns the setting off and removes all audio.
- **Fixtures.** `-e2e-icloud-drive` swaps in `E2ECloudAudioBackend`, a folder in the fixture store whose files upload and download on a clock, and `-e2e-cloud-audio` seeds books another device stored. See `e2e/README.md`.
