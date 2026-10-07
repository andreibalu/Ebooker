# Slice 8: library backup and restore

## Product decision and behavior

Android uses OS Auto Backup for library metadata. Back Up Library defaults on,
requires no purchase, and takes effect immediately. The app cannot read the
system backup switch or confirm that a backup has completed. Settings explains
that Backup by Google must be enabled in Android settings, and opens the system
backup settings with an Android Settings fallback. There is no live multi-device
sync, cross-platform sync, developer-run backend, Google OAuth project, or
"Backed up" status badge.

Settings opens Backed-up Library. Its four mutually exclusive buckets are On
This Phone, Streaming, Audio Missing, and Removed Free Books. Own-book rows
support a trailing swipe with permanent-deletion confirmation. Free-book and
Audiobookshelf rows have no permanent-delete swipe. Metadata shown in each row
includes saved-moment count and progress. Audio Missing offers Locate…, and
removed free books offer Stream when a remote URL is retained. Disconnected ABS
rows explain that their server needs reconnecting.

With backup on, own-book removal deletes the audio copies while preserving the
book, tracks, moments, progress, favorite, EQ, and history. The row leaves the
main Library and Favorites and appears under Audio Missing. Free-book removal
archives the original row and retains its catalog identity and remote URLs.
Stream or re-add from Shelves clears its archive flag in place. ABS removal
continues to remove the Unpaged row only. With backup off, the dialog is a
single destructive Remove from Library plus Cancel; it deletes the app-owned
copies and says the original files on the phone are not touched. This differs
deliberately from iOS, which keeps two options because its files can be
user-visible. On Android app-owned audio is always a private copy and provider
originals are never modified, so retaining it has no value. The earlier
`audiobooks/.removed/` mechanism was unreachable and is gone; startup deletes any
leftover directory.

Import probes orphan fingerprints and offers Restore from Backup, Add as New,
or Cancel. Restore keeps the original book UUID, title, author, progress,
favorite, EQ, moments and reading history while replacing its audio tracks.
Locate compares the complete fingerprint multiset, including repeated-track
counts. Mismatches require explicit Adopt These Files or Choose Different Files.
Add as New proceeds through the existing metadata review. Active-library
imports still reject exact duplicates. Missing and archived books cannot play;
streaming free books whose downloads were lost resolve their remote URLs.

## Storage and backup scope

Schema v5 adds `books.is_archived` with an explicit additive `oldVersion < 5`
migration. The `tracks.fingerprint` column already exists since v1, so this slice
retains it rather than adding a duplicate column. SQLite retains all older
columns, tables and rows. The existing `LibraryStore` interface remains the
repository boundary.

Fingerprints match `LibraryImportService.fingerprint` in the iOS source:
SHA-256 of the complete file at at most 2 MiB, otherwise its first and last 1 MiB,
then little-endian 64-bit file size and duration in milliseconds, encoded as
lowercase 64-character hex. Backfill visits local tracks at launch and hashes
only missing or legacy non-hex identities. Completed identities are never
recomputed. Missing or unreadable files are skipped. Metadata duration rounding
can differ between Android and Apple media APIs; identical bytes and duration
milliseconds produce the same digest. Downloaded LibriVox tracks now also store
this digest. Catalog ID remains the free-book restore identity.

The manifest enables `allowBackup`, `fullBackupOnly` and a custom
`LibraryBackupAgent`. Explicit legacy and Android 12+ allowlists include only
`database/library.db` and `sharedpref/unpaged.xml` for cloud backup and device
transfer. The agent checks the app toggle first: off
stops cloud backup, but on API 28+ a device-to-device transfer
(`FLAG_DEVICE_TO_DEVICE_TRANSFER`) still proceeds; below API 28 off blocks both.
The app process stays live during full backup, so the live `library.db` is never
streamed. The agent builds a consistent snapshot, `databases/library-backup.db`,
by attaching the live file and copying schema and rows inside one transaction
(`VACUUM INTO` needs SQLite 3.27, above minSdk 26), retries up to three times,
and lets `super.onFullBackup` ship it. The XML rules include the snapshot, not
`library.db`, plus `unpaged.xml`. The snapshot is deleted afterwards. On restore,
`onRestoreFinished` replaces `library.db` (and stale WAL/SHM files) with the
restored snapshot before the app opens the library. Audio, download staging, the
separately stored LibriVox catalog, covers and all other files are excluded. The
platform always excludes `noBackupFilesDir`, including ABS
Keystore-encrypted credentials and future model files.

After metadata restoration, startup checks local track files. A downloaded own
book with no audio becomes Audio Missing. ABS rows remain Streaming and need a
server reconnection; no Keystore token can restore. Free books become streaming
entries using retained remote URLs. Cover images are outside SQLite and are not
backed up. Generated covers appear immediately; ABS covers can be fetched again
when the user reconnects and adds/opens server content. No remote LibriVox cover
fetch is introduced.

The host large-library measurement is 15,384,576 bytes for 1,000 books, 20,000
tracks, 20,000 moments, and 50,000 history rows. Preferences add a small XML file.
This fixture fits the 25 MiB Auto Backup quota; arbitrary unbounded libraries or
very large moment notes can exceed it. Android then declines cloud backup until
the payload fits. The app does not claim success. Platform contracts:
[Auto Backup](https://developer.android.com/identity/data/autobackup) and
[BackupAgent](https://developer.android.com/reference/android/app/backup/BackupAgent).

No dependency was added.

## Verification

Host tests cover an actual v4 schema migration to v5 with every metadata table
preserved; backfill and sampled fingerprints; overlap matching and exact
multiplicity; orphan detection; in-place adoption and injected transaction
failure; free-book archival and streaming; ABS non-orphan classification;
persisted toggle; permanent removal and the legacy `.removed` sweep; stale adopt swap folders; snapshot create/install; opening a newer-version database (no-op `onDowngrade`); and the large-library
quota measurement. Existing v1/v2/v3 migration test version expectations advance
to v5 without removing their assertions.

The UI Automator driver adds real local-transport backup/restore through bmgr,
force-stop and pm clear, restored moment/progress/favorite checks and in-place
re-import; a toggle-off backup/restore; and removal, Add as New, Locate mismatch,
archive/stream, all four buckets, permanent swipe deletion and relaunch checks.
The transport is selected on the assigned emulator only. No debug fixture hook
was added to the release app. `make-visual-report.py --backup-only` requires light
and dark captures of settings, missing library, match prompt, four buckets and
removal, plus the updated onboarding storage page. Onboarding now explains
metadata backup and that restored audio needs re-importing. These states have no iOS capture; review uses CloudLibraryView,
RestoreMatchSheet, SettingsDesign, GeneratedCoverView and Color+Theme source.

On 2026-10-07 the following full command passed from `android/` with the brief's
JDK21 and Android SDK environment:

```sh
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest :e2e:assembleDebug :app:assembleRelease
```

Results: debug APK, release APK and E2E driver compiled; 108 host tests passed,
0 failures, errors or skips; 0 lint issues. The release manifest contains the
backup agent and no debug fixture activities. Python report-generator syntax,
runner shell syntax and `git diff --check` also pass.

The full runtime command was attempted:

```sh
ANDROID_SERIAL=emulator-5584 E2E_EVIDENCE_DIR=/private/tmp/unpaged-backup-validation/e2e ./tools/run-e2e.sh
```

It exited 1 before tests, reporting that `emulator-5584` is unavailable. Therefore
0 of the 29 compiled E2E journeys ran, no local-transport backup or restore ran,
and no Android screenshots or visual report were produced. Evidence is in
`/private/tmp/unpaged-backup-validation/`, including build logs, the runner
rejection, host JUnit results, lint report and release manifest. Runtime and
visual acceptance remain open. The guarded runner now reports a missing
assigned serial explicitly before it attempts any emulator operations.

When the assigned emulator is available, run the full suite, then:

```sh
python3 tools/make-visual-report.py <captures> ../docs/android/visual-evidence/ios-reference-1.4.1 ../docs/android/visual-evidence/2026-10-07-backup --backup-only
```

Inspect every light/dark capture and resolve discrepancies before runtime signoff.

## Evidence boundaries

On 2026-10-07 the full suite passed on `Unpaged_E2E_API35_C` with this slice
stacked on slices 7 and 10. The backup journeys cover local transport backup and
restore, Audio Missing, in-place re-import, Locate mismatch, free-book archive and
Stream, and swipe deletion, with light and dark captures.

Even a passing emulator transport test does not establish Google Drive cloud
backup timing, quota behavior on a real account, physical-phone storage/audio
behavior or OEM device-to-device transfer. Those remain unverified. No iOS source,
release metadata, GitHub issue, PR, or public policy page changed.

## Download-removal review fix, 2026-10-07

Removing a LibriVox row cancels its unique WorkManager download before archiving
or deleting the row. The staging cancellation marker also interrupts file copies.
Download promotion now requires an active, non-archived row in the same database
transaction that updates its tracks. The worker rechecks identity before moving
staging and reports failure, rather than success, if removal wins the commit race.
Audio placed by that worker is cleaned up when promotion loses the race.
Explicit Stream or Shelves re-add still reactivates the retained row and allows a
new requested download.

The focused host regression `completedDownloadCannotReviveRemovedStreamingBook`
fails against the original promotion implementation and passes with the fix. It
also verifies moments survive archival and explicit restoration permits promotion.
Build, zero-issue lint and 131 host tests pass. Runtime results follow below.

The existing removal/Locate/archive/Stream/swipe journey passed on API35 emulator
C. The first new removal-during-download journey could not open the card menu
while progress updates refreshed the library; integration with slice 10's
progress-only update fix is required before rerunning that regression.
