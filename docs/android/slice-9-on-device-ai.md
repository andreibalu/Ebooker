# Slice 9: on-device AI

Smart moments and recaps now have a local Android implementation. It passes the emulator E2E suite with real Whisper transcription and a debug fake generator. No physical phone was used, so Gemini Nano itself is not qualified.

## Implementation

`AiCoordinator` owns separate `LocalGenerator` and `SegmentTranscriber` interfaces. Production uses Gemini Nano through ML Kit's Prompt API and whisper.cpp. There is no cloud inference fallback. Audio, prompts, transcripts and generated text never enter the app's network clients. A source-boundary host test rejects network clients in the inference files. The separate `SpeechModelStore` downloads only the pinned public model file. AICore manages its own system model setup/downloads.

Every AI operation rechecks Gemini Nano status and speech-model installation. AVAILABLE plus verified Whisper installation permits AI for local audio. DOWNLOADABLE and DOWNLOADING have explicit Settings download/progress controls. UNAVAILABLE hides feature toggles and player/detail AI actions; Settings explains the unsupported state. Smart save is excluded for streaming books and manual moments remain available. When AI is enabled, streaming detail shows "Audio for this book isn't on this phone."

Settings → On-device AI explains local processing and shows Gemini Nano readiness, the Whisper model's name, 59.7 MB size and MIT license link. Download requires an explicit consent dialog, checks free space, reports bytes, supports cancellation/retry, verifies exact size and SHA-256, then atomically installs. Delete requires confirmation and retains saved moments. Disabling the master switch clears all child settings; disabling Smart summary clears Short progress headline, matching iOS. Model files and partial downloads live in `noBackupFilesDir/speech-model`, never APK assets. Interrupted downloads are discarded on startup. Model verification runs again before native loading.

The Settings toggles follow iOS: Use local AI features, Smart moment naming, Smart summary, and conditional Short progress headline. All start disabled. Onboarding scene 5 describes Android on-device AI and directs listeners to Settings. Payments, Plus and tips remain excluded.

Smart save transcribes the current track from 75 seconds behind through 15 seconds ahead, bounded by its duration. The draft keeps the configured moment-offset timestamp, independently of the analysis window. Opening the player or enabling smart save prewarms Nano. The player shows "Smart Save Moment" and "Analyzing…". Success opens the editable existing moment sheet with an "AI generated" note label. Failure opens the manual draft with "Couldn't analyze this moment." Cancellation never opens a fallback draft.

Generation uses deterministic temperature/top-K settings and 500 output tokens for moments, 300 for recaps. ML Kit typed output is used when that system capability is available. Otherwise the same local Prompt API is instructed to emit JSON. Both paths pass through strict required-key/type/enum validation. Categories and mood use the iOS enums. Name, note, character, quote and headline caps are enforced after generation. Notes/recaps retain at most two sentences and trim incomplete tails. Quotes normalize case, punctuation and diacritics, accept transcript matches, snap near-misses to a transcript sentence at at least 70% word overlap, and discard fabrications. Quotes also enforce 5–20 words. Schema field ordering puts the longer note last and the progress headline before recap.

The complete typed request, including schema, is token-counted before use and must be below 4,000 input tokens. Context overflow retries once with the most recent half of the transcript. Busy errors retry once after 700 ms. Quota, background, unavailable and other failures return the failed path. Cancellation is propagated. No transcript is logged or persisted. Recaps live in `recap_cache.xml`, a separate private preferences store explicitly excluded from Auto Backup and device transfer. First use removes legacy `recap.*` entries from the backed-up `unpaged.xml` preferences. Cache entries require the same track and position; requesting a headline rejects an entry without one so it can be regenerated. Entries are removed when their book is deleted.

Recap transcribes the previous 200 seconds of the current track, ending at saved playback position. Detail shows the iOS sparkle action, loading indicator, "Where Was I?" text and failure copy. Results persist in excluded local recap preferences, bound to exact book/track/position; a changed position invalidates them. No new moment columns were necessary, so SQLite stays at v4. Assigned schema v7 was not consumed.

`MediaExtractor` reads already-decoded WAV PCM directly; compressed tracks pass through `MediaCodec`. Both paths decode the selected window to PCM, average channels and resample to 16 kHz mono. Native Whisper uses CPU inference with at most four threads, automatic language detection (never the phone's locale, so an English book on a German phone is not forced into German), a no-speech threshold and a cancellation abort callback. The native context is cached between transcriptions under the transcription mutex and freed on model delete and on memory pressure (`onTrimMemory` at background level or above, `onLowMemory`). The app logs only window duration and elapsed ASR milliseconds under `UnpagedASR`.

## Pins and sources

| Component | Exact pin | Reason |
| --- | --- | --- |
| ML Kit Prompt API | `com.google.mlkit:genai-prompt:1.0.0-beta4` | System Gemini Nano, local custom prompts and capability/download API |
| ML Kit schema compiler | `com.google.mlkit:genai-schema-compiler:1.0.0-alpha1` | Typed structured generation with enum/list guides |
| KSP | `2.3.6` | Google's documented minimum for the structured-output compiler |
| whisper.cpp | `v1.9.5` | Native offline multilingual transcription |
| NDK | `28.2.13676358` | Reproducible native build and 16 KB page support |
| CMake | `3.22.1` | AGP native build integration |

The native build emits arm64-v8a and x86_64 libraries. Other ABIs are not supported by this slice. No device-quality claim follows from ABI support. There is still one production `app` module; the existing `e2e` driver remains separate.

Google's current [Prompt API setup](https://developers.google.com/ml-kit/genai/prompt/android/get-started) and [structured-output instructions](https://developers.google.com/ml-kit/genai/prompt/android/structured-output) were checked on 2026-10-07. Prompt is beta and structured output is alpha. Release currently does not minify. If minification is enabled later, retain the annotated output classes and generated schema adapters as Google instructs.

Whisper source archive:
`https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz`

SHA-256:
`ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720`

The [ggerganov/whisper.cpp model repository](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1) is pinned to revision `5359861c739e955e79d9a303bcbc70fb988958b1`. `ggml-base-q5_1.bin` is exactly 59,707,625 bytes with SHA-256 `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`. Hub LFS metadata supplied both size and hash, and a host download independently matched the hash. That download is outside the repository and is not included in either APK. The [Whisper license](https://github.com/openai/whisper/blob/main/LICENSE) is MIT. The [whisper.cpp runtime](https://github.com/ggml-org/whisper.cpp/blob/v1.9.5/LICENSE) is MIT.

## Verification

Host checks use the shared brief's JDK21 and Android SDK exports, from `android/`:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest :e2e:assembleDebug :app:assembleRelease
```

Final host result: **138 tests passed, 0 failures/errors/skips**, including **37 AI tests**, and **0 lint issues**. Debug APK, release APK and E2E driver assembly passed. The **28 E2E journeys compile, with 0 executed** because emulator preflight failed. `git diff --check` and Python script syntax checks passed. Earlier compile and missing-x86_64 lint failures were corrected before this run.

`python3 tools/check-ai-release.py app/build/outputs/apk/release/app-release-unsigned.apk` passed. Release DEX contains production Nano/Whisper classes and generated schema providers; it contains no `AiFixtureActivity`, `FakeLocalGenerator`, AI debug preference key or existing fixture activities. Release manifest inspection also found no fixture activities. Neither weights nor test speech files are bundled; arm64-v8a and x86_64 Whisper libraries are present. The small `DebugProbesKt.bin` coroutine-library resource is not a speech model or app fixture hook.

Host evidence: `/private/tmp/unpaged-ai-evidence/` contains the final build log, test/lint reports, summary and release checks. This is local evidence, not a repository artifact.

Two new UI Automator journeys exercise unavailable/manual behavior, consent dismissal, real download cancellation and retry, installation, real speech transcription with a fake generator, editable generated preview, recap, force-stop persistence, deletion and manual fallback. `tools/make-e2e-fixtures.py` synthesizes original test text locally with macOS `say` and converts it to mono 16-bit 16 kHz WAV with `afconvert`. In this sandbox, `say` returned an empty recording. The generator validates frame count and falls back to the checked-in 11-second JFK sample from whisper.cpp v1.9.5, with [provenance and a license note](../../android/tools/fixtures/README.md). This public-domain speech recording is only a picker fixture, outside all APK assets. The fake generator transforms the actual ASR transcript's sentence or a verbatim phrase from the JFK passage into a quote; it never supplies a fake transcript. The debug-only `AiFixtureActivity --es generator available|unavailable|nano` selects it; production always creates `NanoGenerator`.

On 2026-10-07 the full suite passed on `Unpaged_E2E_API35_D` with this slice stacked on slices 7, 8 and 10. The AI journeys load the real JNI model, decode MediaCodec windows, recognize a quote from the JFK fixture, cancel and retry the download, persist the recap across force-stop and delete the model.

Captures are light/dark pairs for AI Settings, feature-toggle options, unsupported Settings, smart player, generated moment preview and recap. `make-visual-report.py` includes these states and pairs the light moment editor with `09-save-moment-light.png`. Other states are source-review gallery entries. SwiftUI AI Settings, moment editor, player loading chip, recap card and shared theme source were read. The captures were reviewed against them.

## Review follow-up

PR #66 review fixes move recap text into the excluded `recap_cache.xml` store and synchronously delete legacy recap entries before library backup reads `unpaged.xml`. Four host regressions cover separate-store persistence, deletion, legacy cleanup with settings preservation, headline-mode invalidation, and the cloud/transfer XML policies.

On 2026-10-07, debug assembly and lint passed with zero lint issues, and all 171 host tests passed on the stacked branch. The focused `whisperConsentRealSpeechSmartPreviewRecapPersistAndDelete` journey passed on `emulator-5586`, `Unpaged_E2E_API35_D`. It generated a recap without a headline, enabled Short progress headline without moving playback, verified the generation action returned, regenerated the headline and verified it after force-stop. This uses real Whisper recognition and the debug fake generator, not Nano. The headline capture was visually reviewed. Local evidence is `/private/tmp/pr66-cache-fixes-e2e-retry/`, with the fresh host run at `/private/tmp/pr66-fresh-tests.log`.

The first focused run failed in the new test's swipe toward the AI sheet's Done button, which dismissed the modal. The retry uses Android Back to dismiss the sheet and passed.

### Second review pass

- Whisper language is `auto`; the old locale-forced call was wrong for books whose language differs from the phone's.
- Free-text fallback output is parsed leniently: code fences and prose are stripped, the first balanced `{…}` object is used, unknown keys are ignored, enums match case-insensitively and invalid categories or mood are dropped rather than failing the save. Name and note remain required.
- Cancellation is reset in Kotlin before the watcher launches (`WhisperNative.reset()`), not on native entry. The model context is cached natively and released on delete or memory trim. Delete, startup partial cleanup, trim and inference share one mutex (`SpeechModelStore.lock`); a download waits for startup cleanup.
- The ML Kit client is closed when `reloadGenerator` replaces it (`GenerativeModel.close()` exists in beta4). Requests carry an explicit `GenerationKind` (moment, recap, recap with headline) instead of inferring the schema from token counts or prompt text. The token guard requires input tokens plus the kind's output allowance to fit in min(model token limit, 4096).
- Whisper markers (`[BLANK_AUDIO]`, `(music)`, `*applause*`, music notes) are stripped; fewer than three remaining words counts as no speech and takes the existing failure path.
- `GenAiException.RESPONSE_GENERATION_ERROR` maps to `GenerationFailure.UNSAFE`, with copy mirroring iOS: "AI detected content likely to be unsafe and couldn't name this moment." and "On-device AI declined to summarize this passage." ML Kit 1.0.0-beta4 has no dedicated safety code, so this mapping is unverified on a real Nano device.
- Unsupported phones keep the "On-device AI" Settings row (as iOS keeps its row) with the unsupported explanation, but the Whisper download card is hidden.
- PCM resampling averages every input sample in each 16 kHz step (box filter, shared by the MediaCodec and raw WAV paths) instead of linear decimation.
- A theme change recreates the activity; the library Settings, AI sheet, consent and delete dialogs all use `rememberSaveable`, so production state survives. The E2E failure was the test swiping toward Done before the restored sheet settled, which drags the sheet closed; `scrollAI` now settles first. Consent and delete dialog flags are saveable too.

## Remaining qualification

The emulator has no AICore. Even after its E2E run passes, Gemini Nano generation quality, latency, model setup/download progress, quotas, background restrictions, structured-output support and device coverage remain unverified until exercised on a supported physical phone. Check Prompt API status on that actual phone; do not infer support from its brand or Android version. Also qualify Whisper on real codecs and longer/multilingual excerpts, Romanian recognition quality, thermal/battery/memory behavior, interruptions, low storage and unreliable model downloads. LiteRT/Qwen for phones without Nano remains a documented follow-up, with no downloaded LLM or invented backend in this slice.
