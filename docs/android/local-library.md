# Local audiobook import and library

Ticket [#59](https://github.com/andreibalu/Ebooker/issues/59), parent Android map
[#49](https://github.com/andreibalu/Ebooker/issues/49). Builds on the native
foundation in PR #58. Allowed paths: `android/**`, `docs/android/**` only.

## Behavior

The system multi-document picker selects audio files without broad storage
permission. The picker accepts generic MIME types so providers can expose M4B
files; imports validate the supported filename extension, an actual audio
track and a positive duration using the platform media stack. Files are copied
immediately to private staging, avoiding long-lived provider grants. The review
shows tracks in natural filename order and editable title/author suggestions
from album/title/artist metadata. A book appears only after all files are ready
and the private index commits. The detail screen lists ordered files and their
durations. Slice 1 now renders the iOS Play/Continue layout with disabled
callbacks pending the Media3 playback slice; see [the current contract](slice-1-shell-library-settings.md).

Natural ordering compares numeric runs without integer overflow, preserving
picker order for equivalent names (`02` / `2`). It is deterministic, but full
Foundation locale collation parity is not claimed. Fingerprints use SHA-256 of
first/last 1 MiB, or the full file at <=2 MiB, followed by little-endian 64-bit
file size and duration milliseconds. This mirrors the iOS algorithm; platform
metadata duration rounding may differ. Duplicate comparison is order-independent
and preserves repeated-track counts. Fingerprints are sampled identity, not
proof of complete byte-for-byte equality.

## Ownership and failure recovery

```text
picker → owned staging → metadata/fingerprints → editable review
       → rename to final UUID directory → SQLite book/track transaction
```

`LocalLibraryRepository` owns filesystem transactions and duplicate checks;
`LibraryStore` isolates the SQLite index, now at version 2 with an additive,
Robolectric-tested upgrade. The parity brief keeps this interface and platform
helper in the single app module; no Room migration is planned for these slices. `LibraryViewModel` serializes operations, performs IO off the main thread,
retains state through rotation and hands Compose lifecycle-aware state updates.

A copy, metadata or duplicate error removes the whole staged selection. User
cancellation is checked between chunks and metadata stages; a blocked provider
read or platform metadata call may delay cancellation until it returns. Pending
preview identity has a cancellation-safe hand-off so a completed preparation
cannot silently leak its staging directory. Save finishes its short commit even
if the UI lifecycle cancels. If the index insert fails, the final directory is
returned to staging for retry. The SQLite transaction rolls back all rows on a
track insert failure.

After process death, startup reads the index before cleanup, removes abandoned
staging and unreferenced UUID directories, and preserves referenced books. If
the index cannot be opened, recovery fails closed and the UI requires retry.
Deletion removes the index first and then owned audio; interrupted deletion
leaves unreferenced files for the same recovery pass. Provider filenames never
become storage paths. Selected originals are never modified. Backup remains
disabled for the SQLite index and audio copies.

## Validation boundaries

Use the build/test command in `android/README.md`. Host regression tests cover
ordering, sampled identity and repeated tracks, failure/cancellation cleanup,
preview retry after index failure, safe removal and restart reconciliation.
Robolectric exercises actual SQLite reopen, ordered rows, foreign-key cascade
and a trigger-induced transaction rollback.

Runtime qualification remains required: actual document-picker flow, local and
cloud providers, revoked access, slow/unknown-size streams, low-space copies,
rotation/process death, corrupt audio, long/VBR MP3 and M4A/M4B, large font,
TalkBack and light/dark screenshots. The dedicated API35 emulator is covered in [the E2E evidence](e2e-visual-validation-2026-10-06.md); handset qualification remains pending. Covers and embedded chapters are future parity work; playback is
the next slice. This is not a public Android release.

Implementation references checked 2026-10-06: [Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files),
[MediaMetadataRetriever](https://developer.android.com/reference/android/media/MediaMetadataRetriever),
[SQLite](https://developer.android.com/training/data-storage/sqlite) and
[Lifecycle](https://developer.android.com/jetpack/androidx/releases/lifecycle).
