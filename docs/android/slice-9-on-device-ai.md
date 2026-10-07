# Slice 9: on-device AI

Smart moments and recaps now have a local Android implementation. Runtime and visual qualification are pending because the assigned `emulator-5586` was absent during this run. No physical phone was used. Do not treat this slice as runtime-qualified or visually signed off.

## Implementation

`AiCoordinator` owns separate `LocalGenerator` and `SegmentTranscriber` interfaces. Production uses Gemini Nano through ML Kit's Prompt API and whisper.cpp. There is no cloud inference fallback. Audio, prompts, transcripts and generated text never enter the app's network clients. A source-boundary host test rejects network clients in the inference files. The separate `SpeechModelStore` downloads only the pinned public model file. AICore manages its own system model setup/downloads.

Every AI operation rechecks Gemini Nano status and speech-model installation. AVAILABLE plus verified Whisper installation permits AI for local audio. DOWNLOADABLE and DOWNLOADING have explicit Settings download/progress controls. UNAVAILABLE hides feature toggles and player/detail AI actions; Settings explains the unsupported state. Smart save is excluded for streaming books and manual moments remain available. When AI is enabled, streaming detail shows "Audio for this book isn't on this phone."

Settings → On-device AI explains local processing and shows Gemini Nano readiness, the Whisper model's name, 59.7 MB size and MIT license link. Download requires an explicit consent dialog, checks free space, reports bytes, supports cancellation/retry, verifies exact size and SHA-256, then atomically installs. Delete requires confirmation and retains saved moments. Disabling the master switch clears all child settings; disabling Smart summary clears Short progress headline, matching iOS. Model files and partial downloads live in `noBackupFilesDir/speech-model`, never APK assets. Interrupted downloads are discarded on startup. Model verification runs again before native loading.

The Settings toggles follow iOS: Use local AI features, Smart moment naming, Smart summary, and conditional Short progress headline. All start disabled. Onboarding scene 5 describes Android on-device AI and directs listeners to Settings. Payments, Plus and tips remain excluded.

Smart save transcribes the current track from 75 seconds behind through 15 seconds ahead, bounded by its duration. The draft keeps the configured moment-offset timestamp, independently of the analysis window. Opening the player or enabling smart save prewarms Nano. The player shows "Smart Save Moment" and "Analyzing…". Success opens the editable existing moment sheet with an "AI generated" note label. Failure opens the manual draft with "Couldn't analyze this moment." Cancellation never opens a fallback draft.

Generation uses deterministic temperature/top-K settings and 500 output tokens for moments, 300 for recaps. ML Kit typed output is used when that system capability is available. Otherwise the same local Prompt API is instructed to emit JSON. Both paths pass through strict required-key/type/enum validation. Categories and mood use the iOS enums. Name, note, character, quote and headline caps are enforced after generation. Notes/recaps retain at most two sentences and trim incomplete tails. Quotes normalize case, punctuation and diacritics, accept transcript matches, snap near-misses to a transcript sentence at at least 70% word overlap, and discard fabrications. Quotes also enforce 5–20 words. Schema field ordering puts the longer note last and the progress headline before recap.

The complete typed request, including schema, is token-counted before use and must be below 4,000 input tokens. Context overflow retries once with the most recent half of the transcript. Busy errors retry once after 700 ms. Quota, background, unavailable and other failures return the failed path. Cancellation is propagated. No transcript is logged or persisted. Recap cache entries are removed when their book is deleted.

Recap transcribes the previous 200 seconds of the current track, ending at saved playback position. Detail shows the iOS sparkle action, loading indicator, "Where Was I?" text and failure copy. Results persist in existing local preferences, bound to exact book/track/position; a changed position invalidates them. No new moment columns were necessary, so SQLite stays at v4. Assigned schema v7 was not consumed.

`MediaExtractor` reads already-decoded WAV PCM directly; compressed tracks pass through `MediaCodec`. Both paths decode the selected window to PCM, average channels and resample to 16 kHz mono. Native Whisper uses CPU inference with at most four threads, system language with automatic detection for unsupported languages or empty output, and a cancellation abort callback. Native contexts are freed after every transcription. The app logs only window duration and elapsed ASR milliseconds under `UnpagedASR`.

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

The focused command attempted:

```sh
ANDROID_SERIAL=emulator-5586 E2E_EVIDENCE_DIR=/private/tmp/unpaged-ai-focused ./tools/run-e2e.sh \
  '-Pandroid.testInstrumentationRunnerArguments.class=dev.unpaged.android.e2e.LibraryE2ETest#onDeviceAiUnavailableKeepsManualMomentsAndConsentIsCancellable,dev.unpaged.android.e2e.LibraryE2ETest#whisperConsentRealSpeechSmartPreviewRecapPersistAndDelete'
```

It failed before installation or instrumentation: `could not connect to TCP port 5586: Connection refused`. A subsequent targeted `adb -s emulator-5586 get-state` reported the device was not found. The brief forbids booting, killing or wiping emulators, so the agent did not start one or use another serial. Runtime E2E pass count is zero. There are no AI captures or ASR timing measurements yet.

The final full-suite command also failed at the same preflight, before executing any test:

```sh
ANDROID_SERIAL=emulator-5586 E2E_EVIDENCE_DIR=/private/tmp/unpaged-ai-evidence/e2e ./tools/run-e2e.sh
```

The failed attempt log is `/private/tmp/unpaged-ai-evidence/e2e-full-attempt.log`. The runner never reached capture-directory setup. There is no E2E screenshot evidence directory; `/private/tmp/unpaged-ai-evidence/e2e` is the intended location for the next successful run.

Intended captures are light/dark pairs for AI Settings, feature-toggle options, unsupported Settings, smart player, generated moment preview and recap. `make-visual-report.py` includes these states and pairs the light moment editor with `09-save-moment-light.png`. Other states are source-review gallery entries. SwiftUI AI Settings, moment editor, player loading chip, recap card and shared theme source were read; visual review still requires real captures.

## Remaining qualification

Run the complete suite on the assigned emulator, then open every new light/dark capture and correct geometry, keyboard reachability, ordering, typography and colors. Confirm real JNI model loading, MediaCodec window decoding, recognized quote, cancellation, model deletion, recap persistence and no background result leak. Record `UnpagedASR` timings for both windows. Host compilation and pure tests do not prove these runtime boundaries.

The emulator has no AICore. Even after its E2E run passes, Gemini Nano generation quality, latency, model setup/download progress, quotas, background restrictions, structured-output support and device coverage remain unverified until exercised on a supported physical phone. Check Prompt API status on that actual phone; do not infer support from its brand or Android version. Also qualify Whisper on real codecs and longer/multilingual excerpts, Romanian recognition quality, thermal/battery/memory behavior, interruptions, low storage and unreliable model downloads. LiteRT/Qwen for phones without Nano remains a documented follow-up, with no downloaded LLM or invented backend in this slice.
