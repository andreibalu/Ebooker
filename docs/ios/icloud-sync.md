# iCloud sync

Read this before changing anything that syncs, deletes or restores a library record: the sync gate, the CloudKit container, orphan detection, fingerprints, restore on re-import, archived free books, Cloud Library, audio in iCloud, the backup badge or delete copy.

iCloud sync is free for anyone signed in to iCloud; it is not part of Plus (see `purchases.md`). The `"synced"` SwiftData configuration (library, progress, moments, EQ, reading sessions, covers) goes to the CloudKit private database of container `IcloudSyncGate.containerIdentifier`. Audio files sync only when the user stores them in iCloud (see "Audio in iCloud"); otherwise each device re-acquires them.

## The gate

`IcloudSyncGate` is the single decision point: sync-sensitive behavior calls `IcloudSyncGate.isEnabled()` rather than reading the toggle. The deliberate exceptions are the captions in `ICloudSettingsView`, the Settings root and the onboarding iCloud scene, which compare the stored preference with the gate to say a change applies after relaunch. Each checks the account first: signed out, the preference can be on (an upgraded subscriber's) while sync never starts, so no caption may promise it on reopen. The gate requires the `iCloudSyncEnabled` preference and a signed-in iCloud account (`ubiquityIdentityToken`). It is computed once per process, so a toggle change takes effect after relaunch: the SwiftData container can't switch databases while it runs. When it is false, `AppDelegate` builds the container with `cloudKitDatabase: .none`.

- **Opt-in.** The preference defaults to off. It is offered in Settings → iCloud Sync and on the onboarding iCloud scene, both bound to the same key. Turning sync on silently for existing users would start uploading covers and change what Remove does (archive and keep instead of delete), so nobody gets it without asking.
- **Upgrading from Plus-gated sync.** Plus used to be a second condition. The preference key and its meaning didn't change, so a subscriber with sync on keeps syncing through the update. Someone whose Plus lapsed while the toggle was on gets sync back on the first launch after the update, because that was their last choice and the old screen hid the toggle from them. Records they deleted while sync was off come back from CloudKit as "In iCloud only" books; swipe-to-delete in Cloud Library removes them for good.
- **Turning sync off** asks first when this device's store sees audio in iCloud: keep it for other devices, or remove it everywhere. With sync off, Settings → iCloud Sync still looks at the container (`CloudAudioStore.inspectWithoutSync`, read-only) so audio left there stays visible and removable, since it keeps counting against the user's quota.
- **Fixtures.** DEBUG E2E fixture launches always build the local store. In them `hasUbiquityIdentity()` answers `-e2e-icloud-account` instead of the real account, so the gate, its relaunch rule and every sync-on surface run without CloudKit.

## Record states

A book's state comes from its synced flags plus one per-device answer; use `Audiobook`'s computed properties instead of combining them:

- `isDownloaded`: the audio is on this device. Per device, never synced (see below).
- `isStreamingOnly`: not downloaded here, and a free or Audiobookshelf book.
- `isCloudOnlyOrphan`: an own (imported) book whose audio is missing here. Restorable via "Locate…".
- `isArchived`: a free book the user removed from their library while sync was on. It syncs on purpose, because removing a book from the library removes it on every device. The record and remote URLs stay. A free book that isn't downloaded here may be streaming or removed, so this flag is what tells them apart. Another device may still have the files of a book archived elsewhere; un-archiving keeps them.
- `isInActiveLibrary`: belongs in the grid, CarPlay and Siri on this device.

## Downloaded is per device

The synced record is shared by every device, so it can't say whether this device has the audio. When it did (`_isDownloaded`), one device's state overwrote another's: a new device that joined sync marked books not downloaded, which synced back and moved the first device's books into "In iCloud only" though their files were there, and Download or Remove from this iPhone on one device rippled to the rest.

- **Invariant.** `Audiobook.isDownloaded` reads and writes `DeviceDownloadState`, a plist in Application Support keyed by book id, which never syncs. No code path writes this device's download state into a synced field, so two devices can't flip each other's answer back and forth.
- **Files decide when there is no answer.** With no entry (the first launch after the update, a record that just arrived from another device, a write lost to a crash), `Audiobook.hasLocalAudio()` answers from `Application Support/Audiobooks/<folderName>/`: an Audiobookshelf book needs every track file, a book with a streaming-only track has none, and any other book counts once its folder has a file. Every explicit write agrees with what the files then show, so a lost write rebuilds to the same answer.
- **`OrphanDetectionService`** settles books with no entry from their files, flips a downloaded book whose files went away to not downloaded, and drops entries for deleted books. It never flips a book to downloaded because files appeared: a download in progress would count early.
- **`_isDownloaded` stays in the schema** (a CloudKit-backed model can't drop a field) and is written once, at creation, for app versions that still read it. This version never reads it. Devices on an older version still trade the flag among themselves until they update.
- **Writes are immediate.** An explicit change (`set`, a rollback's `restore`) writes the plist before returning. A background download session finishes, calls the system completion handler and may be suspended or killed at once, and a lost `true` stays lost, because files appearing never flip a book to downloaded. Only answers the fallback computed from files are batched, since they rebuild the same way.
- **Rollback.** `ModelContext.rollback()` can't see the store, so library mutations snapshot it and pass the snapshot to `LibraryMutationTransaction.rollbackAndRethrow`.
- **Fixtures.** `-e2e-other-device-flags`, `-e2e-forget-device-downloads` and `-e2e-other-device-import-after` play another device's sync and the first launch after the update; see `E2EFixtures.applyOtherDeviceSync`.

## Orphans

`OrphanDetectionService` runs at launch and, while sync is on, after each successful CloudKit import event (`NSPersistentCloudKitContainer.eventChangedNotification`). A downloaded own book whose folder is missing or empty flips to not downloaded on this device; files are never deleted. An Audiobookshelf book with any missing track returns to streaming instead.

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

With sync on, deleting a record deletes it on every device, so its audio in iCloud goes too (`CloudAudioStore.bookDeleted`), and the Cloud Library dialog names the audio when there is some. Before iCloud Drive has reported what it holds, the delete is queued (see "Queued work") and the dialog says "any of its audio stored in iCloud". With sync off the record still exists in iCloud for other devices, so a local delete never touches cloud audio.

`ContentView`'s delete dialog branches by book kind (Audiobookshelf, streaming, downloaded free, own) and, for own books, on `IcloudSyncGate.isEnabled()`. With sync on, an own book gets one non-destructive option, "Remove from this iPhone", which drops local audio and keeps the record; a second local option is left out on purpose. Its message says whether the audio stays in iCloud, from the book's `CloudAudioState`.

## Backup badge

`ICloudBackupBadge` ("Backed up to iCloud", as a cover overlay and inline on detail) renders whenever the gate is on. `NSPersistentCloudKitContainer` exposes no per-record sync status, so the badge is a static statement that synced-store records are backed up, gated so it never promises backup to someone without sync. Cloud Library's row labels ("Saved", "Backed up") follow the same gate: with sync off the page is still reachable from Settings → iCloud Sync, and its rows make no backup claim.

## Audio in iCloud

`CloudAudioStore` keeps optional copies of own (imported) books' audio in the app's iCloud Drive ubiquity container, in `<container>/Audiobooks/<folderName>/<storedFileName>`, which mirrors local storage under the book's synced `folderName`. Another device, or this one after a reinstall, downloads the book from Cloud Library instead of locating the file again.

- **Why iCloud Drive and not CloudKit assets.** The system daemon uploads and downloads in the background, resumes and retries, follows the user's iCloud Drive cellular setting, and reports per-file progress through `NSMetadataQuery`. CKAsset records would need a custom zone, schema deployment to the production CloudKit environment, our own long-lived operations and retry, and whole-file transfers. Both count against the same iCloud quota. The cost is that iCloud Drive must be on for the account and for Unpaged; `CloudAudioStore.availability` reports `.driveUnavailable` otherwise.
- **Capability.** The entitlements add `CloudDocuments` and `com.apple.developer.ubiquity-container-identifiers` for the existing container. The App ID's iCloud capability (`XCODE_6`) and its profiles already grant both, so the developer portal needed no change.
- **No extra local space.** `ICloudDriveAudioBackend.copyIn` clones the file into tmp and hands the clone to iCloud with `setUbiquitous`. APFS clones share blocks, so the cloud copy costs nothing locally until one side changes. The folder sits outside `Documents`, so the Files app doesn't show it.
- **Needs sync.** The store is active only while the gate is on this launch, because the synced record is what tells another device the book exists.
- **Own books only.** Free LibriVox books and Audiobookshelf books download again from their source, so copying them would spend the user's quota for nothing. `CloudAudioStore.isEligible` excludes them.
- **The choice.** `iCloudAudioEnabled` is per device and defaults to off: one iPhone may hold books too large for the account's quota. On, it stores each new import and each book whose audio this device replaces. Turning it on offers to store every book already here, with the estimated size; turning it off offers to remove all audio from iCloud, warning about books this iPhone doesn't have. The detail screen's `CloudAudioBookCard` stores or removes one book regardless of the setting.
- **What "stored" means.** `CloudAudioState.derive` is `.stored` only when every track's file is in the folder and fully uploaded. Download, the delete copy and "the audio stays in iCloud" all depend on that, so a file still uploading or missing must never count. `CloudAudioStateTests` hold the rules.
- **Queued work.** Until iCloud Drive answers and the first metadata report arrives (the first seconds of a launch, or every launch while iCloud Drive is off), `files` is incomplete. Adds, replaces, merges and record deletes from that window wait in per-device UserDefaults queues (`CloudAudioStore.pendingUploadsKey`, `pendingDeletesKey`) and run at the first report, before maintenance, so a queued replace clears a folder before maintenance would resume it. Maintenance doesn't store every downloaded book with no cloud files instead: that would re-upload a book the user removed from iCloud on purpose.
- **Same file, same moment.** Two devices storing one book can race: the other device's copy lands at the destination before the metadata reports it, and `copyIn` fails. `CloudAudioBackend.hasSameFile` treats a file of the same name and size there as done. The name ties it to the same track of the same record; a legacy `.icloud` placeholder has no readable size, so its presence is enough.
- **Never overwrite or delete on resume.** At the first report each launch, a book with a partial cloud folder and local files gets its missing files copied in. Resuming never overwrites or deletes, since another device may be uploading a newer copy right now. Only the device that replaces a book's audio (Locate…, restore on import, merge) clears and re-uploads the folder (`bookAudioReplaced`). A merge deletes the local book's folder and uploads to the cloud entry when the local book had audio in iCloud, even with the setting off. Two devices storing the same file make an iCloud Drive conflict; the copies are identical, so the monitor keeps the current version.
- **Remove from this iPhone** keeps the cloud copy and evicts this device's downloaded copy of it, or the clone would keep the space the user meant to free. Files still uploading can't be evicted; launch maintenance evicts them later for books that are no longer downloaded here. While this device is still copying a book's files in, the files not yet copied exist only here, so the dialog says iCloud won't have the whole book.
- **Download** asks iCloud for each file, tracks progress from the metadata, then moves the files into local storage through a `LibraryMutationTransaction` and sets `isDownloaded` for this device only. The track records already describe the files, so nothing else changes.
- **No sweep of folders without a book.** A new device's CloudKit import arrives in batches, so a folder whose record hasn't arrived yet looks orphaned. Folders left behind by a record deleted on an older app version stay until the user turns the setting off and removes all audio.
- **Fixtures.** `-e2e-icloud-drive` swaps in `E2ECloudAudioBackend`, a folder in the fixture store whose files upload and download on a clock, and `-e2e-cloud-audio` seeds books another device stored. `-e2e-icloud-drive-delay` holds the container lookup and `-e2e-icloud-race` lands another device's copy first. See `e2e/README.md`.
