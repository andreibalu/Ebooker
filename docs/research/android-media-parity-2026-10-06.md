# Android media, import and integration parity

Research: 2026-10-06. Ticket: [#53](https://github.com/andreibalu/Ebooker/issues/53), parent [#49](https://github.com/andreibalu/Ebooker/issues/49). Scope: mirror current core app, excluding payments and Apple sync. Research only; no Android implementation or architecture decisions. Earlier local-only MVP advice in `android-port-2026-10-06.md` is not the scope of this investigation.

Source baseline: repository HEAD `85d6a62`; current dirty main checkout also inspected read-only, especially `AudioPlayerManager.swift`, `LibriVoxAPIClient.swift` and `AppDelegate.swift`. Artifact produced on `research/android-media-parity` in `/private/tmp/unpaged-android-media-parity`. Source findings below describe inspected code, not simulator/device qualification.

## Finding

Android has documented APIs for the required playback, local import, catalog streaming/downloads, ABS integration, EQ processing and car integration. This establishes feasibility candidates, not complete parity. The largest unresolved compatibility checks are long-file seeking/metadata, durable download lifecycle, credential refresh during streaming, exact DSP behavior and Android Auto voice/privacy. Product and architecture choices remain with the human.

## Current behavior that must be mirrored accurately

| Area | Source evidence / observed semantics |
| --- | --- |
| Playback | `Pageless/Services/AudioPlayerManager.swift`: shared AVPlayer owner; load/seek generations reject stale work; playback rate, skip/backtrack, timer, remote controls, interruptions, stats and persistence are coordinated there. |
| Current position versus progress | `Services/PlaybackPersistence.swift`: saves current track/time/rate at >=5 second movement or forced boundaries; high-water progress is separate; seeking can impose a 180-second penalty before increasing the high-water mark. |
| Activity | `Services/ReadingSessionRecorder.swift`: wall-clock listening, hour buckets, five-minute chunks, <30-second discard; metadata snapshots survive book deletion. |
| Import | `Services/LibraryImportService.swift`: natural filename ordering; album/title/artist/artwork extraction; owned copies and ordered tracks. Current fingerprint is SHA-256 of first+last 1 MB (or whole file <=2 MB), little-endian size and duration milliseconds. Fingerprint matching uses multiplicity, not a set that collapses repeated tracks. AGENTS.md's older first-16-byte summary is stale. |
| Chapters | No embedded local M4B chapter-group reader was found in importer/playback/model searches. UI previous/next chapter navigates `AudioTrack` files. ABS has chapter metadata but `AudiobookshelfLibraryService.trackTitles` maps titles onto file tracks (same count or near a file start), rather than constructing arbitrary embedded sub-track chapters. Do not turn a desired enhancement into an existing parity promise. |
| LibriVox | Catalog API/cache, curated shelves, alternatives and deterministic daily pick; stream/add/download identity reuse. `Downloads/LibriVoxBackgroundDownloadCoordinator.swift`, `LibriVoxDownloadJob.swift`, `LibriVoxDownloadManifestStore.swift` and `LibriVoxDownloadRuntime.swift`: persisted jobs/attempt IDs, cancellation/retry, relaunch handling and staged finalization. Shared UI download lifetime is wider than an individual detail screen. |
| ABS | `Services/AudiobookshelfClient.swift`: login/API key, single-flight refresh keyed by connection identity, server-origin checks, tokenless stored URLs, runtime stream credentials. `Services/ABSAccount.swift`: progress pushes are detached, errors logged/dropped; no durable offline progress queue is implied. `AudiobookshelfLibraryService.swift`: converts global server time to local track position and back. ABS remains streaming-only. |
| EQ | `Models/EqualizerSettings.swift` and `Services/EqualizerTap.swift`: **60/230/910/3600/14000 Hz**, peaking biquads, preamp and soft tanh limiter. These are actual source frequencies; AGENTS.md's older 250/1000/4000 values are stale. Per-book settings/presets are persisted. |
| Car voice | `Services/CarPlayVoiceSearch.swift`: checks on-device recognition before starting audio capture and sets `requiresOnDeviceRecognition=true`. Privacy is part of the behavior, not just the presence of a microphone button. |

These are local source paths relative to `Pageless/`, inspected on the baseline/current checkout. No iOS files were edited.

## Android evidence and parity constraints

### Playback, interruption and process death

Media3 documents a player/session hosted in `MediaSessionService`, or `MediaLibraryService` when serving a browseable library, with a UI `MediaController`. It handles system/headset controllers and media notifications; requires foreground-service declarations. Resumption is opt-in and the app must persist its playlist/position/metadata. Dismissing recents is different from killing the process or explicitly stopping the app. [Background playback](https://developer.android.com/media/media3/session/background-playback)

Android 13 Task Manager Stop removes the entire app and stops playback; the app does not receive a cleanup callback at that moment. Therefore periodic durable position/stat writes are needed; a lifecycle finalizer cannot guarantee every last second survives. Explicit force-stop and OS reclamation must be separate test cases; do not promise uninterrupted playback through either. [User stopping foreground apps](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping)

ExoPlayer can own audio-focus management via its audio attributes. Speech content has different automatic duck/fade behavior from music; targeting API35+ requires top-app or foreground-service status to request focus. Verify actual spoken-book interruption/resume behavior rather than copying music defaults. [Audio focus](https://developer.android.com/media/optimize/audio-focus)

### File access, formats and chapter identity

SAF lets the user choose documents; persisted URI access does not prevent a source moving/deletion. Copy import into app-owned storage is a feasible equivalent to current iOS ownership; provider streams may have unknown sizes or slow reads, so disk estimates and fingerprints cannot assume ordinary seekable file paths. Do not require all-files permission merely to reproduce a picker workflow. [SAF](https://developer.android.com/training/data-storage/shared/documents-files)

Media3 supports MP3/MP4/M4A containers, but codecs depend on platform decoders; some MP3 streams have seeking limitations. MP4-container support is not proof that every M4B tag/chapter format is exposed. Test container sniffing, extension/MIME combinations, metadata and VBR position accuracy independently. Current iOS parity is ordered playable files; accepting arbitrary embedded chapters would be a separate human scope choice. [Formats](https://developer.android.com/media/media3/exoplayer/supported-formats)

Android model IDs must remain stable across file copy, failed import and retry. Preserve natural ordering, duplicate multiplicity, source catalog IDs and book-global time conversion. Kotlin/Java filename comparison and duration rounding are not automatically equivalent to Foundation; fixtures should make them explicit.

### Durable LibriVox downloads

Media3 supplies `DownloadManager`, `DownloadIndex`, cache and `DownloadService`, with requirements and bounded concurrency. Persisted stop reasons survive process restart, while global pause state is runtime only. These primitives do not themselves supply Unpaged's whole-book atomic promotion, library identity reconciliation or attempt-generation/cancellation invariants. A cache-backed download is also not automatically a standalone imported file layout. [Downloading media](https://developer.android.com/media/media3/exoplayer/downloading-media)

User-initiated data-transfer jobs are another documented mechanism, introduced API34 for long user-started transfers. On API35+, `dataSync`/`mediaProcessing` foreground services have a six-hour-per-24-hour background budget; those documented limits are not the same as `mediaPlayback`. The implementation choice must account for older devices and interrupted multi-hour downloads. [UIDT](https://developer.android.com/develop/background-work/background-tasks/uidt), [Foreground timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout)

The catalog client's lenient envelopes, transient retry and offline classification can be reproduced as API behavior. LibriVox's feed contract is public; access to feeds is not an unlimited-traffic or universal public-domain-in-every-country guarantee. [LibriVox API](https://librivox.org/api/info)

### ABS credentials and progress

ABS documents library/items, playback and user media progress APIs. Port current server/client fixtures too: the public reference is not comprehensive for the newer `/auth/refresh` contract used by this repository. Preserve refresh identity and origin checks, logout cancellation and global-time mapping. Consider Authorization headers for Android streaming only after verifying the server's ranged requests and redirect behavior; token injection is not an unavoidable Android constraint. [ABS reference](https://api.audiobookshelf.org/)

Android Keystore manages keys, not arbitrary token values: encrypt persisted secrets with protected keys and assess backup/restore rules. Redact request URLs/headers; persisted AudioTrack URLs remain tokenless. Android's network-security configuration controls cleartext trust and differs from Apple's local-network exceptions; local HTTP/private-address support needs an explicit compatibility/security test, not blanket cleartext. [Keystore](https://developer.android.com/privacy-and-security/keystore), [Network configuration](https://developer.android.com/privacy-and-security/security-config)

### EQ and Android Auto / voice

Android's framework Equalizer exposes device band count, center frequencies and gain ranges; it does not promise the five exact source bands, preamp and tanh limiter. Media3's PCM `AudioProcessor`/audio-sink customization makes a custom DSP candidate possible. Verify processor activation, sample formats, speed changes, clipping and effects of offload/passthrough before claiming exact tonal parity. [Equalizer](https://developer.android.com/reference/android/media/audiofx/Equalizer), [AudioProcessor](https://developer.android.com/reference/androidx/media3/common/audio/AudioProcessor), [Audio sink builder](https://developer.android.com/reference/androidx/media3/exoplayer/audio/DefaultAudioSink.Builder)

Android Auto consumes the phone media app's browse/session interfaces and needs manifest declarations and car-quality checks. It is not a copied CarPlay layout, and Android Automotive OS is a separate target. Browse trees, recent books, chapters/skip actions, bookmarks, speed and disconnected-source errors require host-specific verification. [Auto support](https://developer.android.com/training/cars/media/auto), [Serving a library](https://developer.android.com/media/media3/session/serve-content)

Car voice actions are recognized/interpreted by Android Auto/AAOS and delivered as search/play callbacks. App-provided local voice search instead can use API31's `isOnDeviceRecognitionAvailable`/`createOnDeviceSpeechRecognizer`; generic recognition may use remote services. The documented host voice path is not evidence that the host uses on-device recognition. Privacy copy must distinguish host recognition from Unpaged's own recording/transcription. [Car voice](https://developer.android.com/training/cars/media/voice-actions), [SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)

## Concrete spikes and acceptance evidence

Proposed experiments, not architecture approval or completed tests:

| Spike | Evidence needed before asserting parity |
| --- | --- |
| Service + resumption | Screen-off two-hour playback; Bluetooth disconnect; phone call/navigation interruption; process kill, recents dismissal, reboot and Task Manager Stop separately; durable current/high-water position and stats reconciliation. |
| Import/provider corpus | Local files and a cloud document provider, unknown size, cancelled/revoked access, low space, failed copy, repeated tracks and natural names `1/2/10`; import leaves one valid library identity and no half-ready book. |
| Long audio/metadata | CBR/VBR MP3, multi-hour M4A/M4B, artwork/tags, corrupt duration, actual seek offsets; separately document whether embedded chapter formats can be read and whether that is desired scope. |
| Download recovery | Multi-track book, app kill/relaunch, network loss, missing Range support, partial files, changed source, cancellation during finalization, retry and existing streaming row promotion; progress coherent in all routes. |
| ABS streaming auth | Session expiry during ranged requests, concurrent401s, API key rejection, logout/server switch while refresh pending, redirect to another origin, two-track global position restore/report and offline failure. Match current fire-and-forget progress rather than imply guaranteed offline sync. |
| DSP | Impulse/sweep/known PCM against iOS coefficients, all source bands/presets, preamp limiter, mono/stereo/sample-rate changes, speed changes, track boundary, hardware offload and CPU/power on weaker phone. |
| Car + voice | Desktop Head Unit then real car: browse/search/empty search, speed/skip/bookmark actions, disconnect/reconnect, locked phone, unavailable source; local recognition availability/model/locale and host-recognition disclosure. |

## Candidate device/API floors (human decision pending)

**API26 / Android8** is a candidate broad core floor, conditional on chosen current Compose/Media3/Room dependency versions. It requires fallback treatment for UIDT (API34) and local voice (API31). **API31 / Android12** is a candidate simpler voice-capable floor but does not guarantee a speech model/service. **API34 / Android14** simplifies UIDT availability but reduces device reach. These are alternatives, not a selected minimum or library-version compatibility certification. API floor is distinct from Play target requirements.

Proposed physical qualification: a Pixel and Samsung plus one slower device at the chosen floor; current-target/API35+ foreground/focus behavior; Bluetooth headphones; Android Auto head unit. Emulator/DHU testing is useful but does not qualify OEM background restrictions, real audio hardware/offload or car-host behavior. No such tests were run here.

## Completion boundary

Research question answered with current source mapping, primary API evidence and named uncertainties/spikes. Native Android primitives plausibly cover core functionality; **exact parity remains unverified** until implementation and the evidence above exist. No architecture, minimum API or feature-exclusion decision is made by this note. No app code, release, credentials or parent map changed.
