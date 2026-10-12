# Android agent instructions

This subtree is the native Android Unpaged app: a Kotlin/Compose mirror of the
core iPhone app. It excludes payments (Plus, tips), Apple Intelligence, iCloud
and any live or cross-platform sync backend. Root Xcode, SwiftUI, StoreKit and
iCloud instructions do not apply here. `README.md` has the build, test and E2E
commands.

The product and architecture decision index is the
[Android Wayfinder map](https://github.com/andreibalu/Ebooker/issues/49);
tracker operations are in `../docs/agents/issue-tracker.md`. All ten
implementation slices are merged. Physical-device testing is next:
`../docs/android/physical-test-checklist.md`.

## Rules

- Work under `android/` and `docs/android/` only unless explicitly authorized.
  Do not edit `Pageless/`, `PagelessTests/`, `e2e/`, Xcode state or release
  metadata as part of Android work.
- Native iOS code is the behavior spec. Match its copy, defaults and rules unless
  an Android adaptation below says otherwise; iOS tickets are not Android
  instructions.
- Keep the single production `app` module plus the separate `e2e` driver until
  an architecture decision justifies more modules.
- The Play application id is `app.unpaged` and is permanent. Debug builds keep
  `dev.unpaged.android.development`, so E2E, fixtures and `adb` commands target
  that id and install beside the Play build. minSdk stays 26.
- Raise `versionCode` for every Play upload. The release bundle is signed with
  the upload key from `~/.config/unpaged/upload-signing.properties` (outside the
  repo); Google Play App Signing holds the app signing key. Release steps and
  store text live in `android/play/` (see `android/README.md` → Google Play).
- Use the checked-in Gradle wrapper and process-local JDK/SDK variables. Never
  install global Gradle or edit shell profiles. Pin exact dependency versions;
  update the checksum with any wrapper change. No automatic license acceptance.
- Keep SDK paths, signing keys, tokens, generated outputs and `local.properties`
  out of Git.
- Every change runs `:app:assembleDebug :app:lintDebug :app:testDebugUnitTest`
  (zero lint issues). UI or behavior changes also run `tools/run-e2e.sh` on a
  dedicated `Unpaged_E2E_*` emulator, and their captures get a visual review.
- The owner's test phone, Galaxy A54 `RZCW60SZE3H` (fresh install, no SIM,
  Wi-Fi only), is approved for installs, E2E runs and physical checks without
  asking. Address it by serial. Never use any other physical device.
- Follow `../AGENTS.md` → Testing for both platforms: E2E is the preferred sole
  testing mechanism; isolated tests require a written failure analysis before
  implementation and must catch bugs the E2E assertions miss. The host command
  above runs only the retained isolated regressions, not a requirement to add
  unit tests. Preserve repeatable E2E evidence as defined there.
- Emulator runs do not qualify physical phones, Android Auto head units, Gemini
  Nano or Google Drive backup. Say so in PR evidence. Put run logs and evidence
  in the PR, not in the repository.
- Debug-only fixture code lives in `app/src/debug/`. The release APK must contain
  no fixture activity, intent extra or fixture asset.

## Architecture

Packages under `dev.unpaged.android`: `library`, `playback`, `shelves`, `abs`,
`moments`, `equalizer`, `activity`, `backup`, `ai`. The root package holds
`MainActivity`, `OnboardingScreen`, `SettingsScreen`, `UnpagedPreferences` and
`UnpagedTheme`.

### Persistence

- `SQLiteLibraryStore` (`library.db`, schema **v5**) behind the `LibraryStore`
  interface; no Room. Migrations are explicit additive `onUpgrade` steps with
  Robolectric upgrade tests. Never drop or replace a user table.
- Streaming tracks store `storedName = ""` plus a remote URL. Never resolve an
  empty stored name into a local file.
- `reading_sessions` deliberately has no foreign key to books, so history
  survives deletion.
- `UnpagedPreferences` is the only SharedPreferences wrapper (`unpaged.xml`).
  Keys mirror the iOS `@AppStorage` names and defaults. Recaps live in a separate
  `recap_cache.xml`, excluded from backup.
- The LibriVox catalog is a separate `librivox-catalog.db` with a
  transactionally committed sync cursor.
- Imports copy audio into private `audiobooks/<UUID>/`. Provider originals are
  never modified or deleted.

### Playback

- `PlaybackService` is a Media3 `MediaLibraryService` owning one ExoPlayer.
  `PlayerController` is the process-wide state owner shared by the phone UI,
  system controllers and car clients.
- iOS rules: resume backtrack once per process launch, 180 s marker penalty after
  a load or scrub, 5 s position-save delta plus forced writes on
  pause/track/seek/speed/background/finish, previous-chapter five-second rule.
- Chapters come from `Mp4Chapters` (Nero `chpl` and QuickTime text tracks,
  including `und`, cached in a sidecar), Media3 ID3 CHAP, ABS chapters, or one
  per file.
- EQ: `EqualizerAudioProcessor` is always in the audio sink (PCM16; float output
  disabled) so changes apply live. Five RBJ peaking bands at
  60/230/910/3600/14000 Hz and the iOS soft limiter. Per-book JSON in
  `equalizer_json`.
- `ReadingSessionRecorder` ticks every second while playing, emits 5-minute
  chunks, flushes on pause/track/book/background/finish and drops chunks under
  30 s.

### Shelves (LibriVox)

- `LibriVoxClient` mirrors the iOS hardening: error envelopes, the 404 no-match
  sentinel, `extended=1`, strict query encoding.
- Catalog sync runs only while Shelves is in the foreground: 50-book pages,
  curated preload first, 24 h refresh. No background catalog work.
- Streaming addition reuses the `catalogId` row. Downloads are unique WorkManager
  jobs per catalog ID with a foreground `dataSync` notification and
  `Range`/`If-Range` resumption. Promotion keeps the book's identity, progress,
  moments and EQ.
- Samples use an independent `MediaPlayer`: 20 s starting 30 s in.
- LibriVox covers are always generated. Do not add remote cover fetches.

### Audiobookshelf

- Credentials are AES-256/GCM encrypted with an Android Keystore key in
  `noBackupFilesDir/abs-credentials.enc`. Never in preferences or SQLite.
- Stored stream URLs are token-free. A Media3 `ResolvingDataSource` appends the
  token at open time and refreshes login sessions with under 45 minutes left.
- The network security config permits cleartext for self-hosted servers. Public
  HTTP hosts get the iOS warning before credentials are sent. Credential-bearing
  requests do not follow redirects.
- Progress is PATCHed fire-and-forget through one ordered queue.

### Android Auto and system

- Car browse root: Favorites, Library, Shelves, plus Chapters while a book is
  loaded. Custom commands: playback rate, Save Moment, Mark Progress.
- `onGetSession`/`onGetLibraryRoot` allow only the app, Android-trusted
  controllers, Android Auto and Automotive. Media IDs are app-owned; arbitrary
  controller URIs are rejected.
- Voice search and the static **Play Latest Book** shortcut share one resolver.

### Backup (Android's replacement for iCloud)

- OS Auto Backup through `LibraryBackupAgent`. It ships a consistent snapshot
  (`library-backup.db`) plus `unpaged.xml` only. Audio, covers, the catalog,
  staging, credentials and model files are excluded.
- The in-app Back Up Library toggle defaults on. With backup on, removing an own
  book deletes audio but keeps its metadata (Audio Missing). Free books are
  archived (`books.is_archived`). With backup off, removal is a single destructive
  action.
- Track fingerprints use the iOS `LibraryImportService.fingerprint` algorithm.
  Re-import offers Restore from Backup or Add as New.

### On-device AI

- `AiCoordinator` composes `LocalGenerator` (Gemini Nano via the ML Kit Prompt
  API) and `SegmentTranscriber` (whisper.cpp). There is no cloud fallback.
- The Whisper model (`ggml-base-q5_1.bin`, 59.7 MB, pinned revision and SHA-256)
  is downloaded only after explicit consent into `noBackupFilesDir/speech-model`.
  It is never an APK asset.
- Check capability at runtime before every operation. Never infer support from
  brand, chipset or Android version. All AI toggles default off.
- Post-processing mirrors iOS: verified quotes, sentence trimming, field order,
  token budget.
- Release does not minify. If minification is enabled, keep the ML Kit annotated
  output classes and generated schema adapters.

### Onboarding adaptations

Seven scenes, like iOS. Permissions asks only for notifications (API 33+, never
blocking playback). The moments and library scenes describe Android behavior. No
purchase, Plus or iCloud controls.

## Known gaps

- Phones without Gemini Nano get no AI features. A LiteRT-LM fallback
  (Qwen3-0.6B or Gemma 3 1B) was researched but not built.
- No Audiobookshelf downloads.
- The Settings Done capsule is black on Android and grey on iOS.
