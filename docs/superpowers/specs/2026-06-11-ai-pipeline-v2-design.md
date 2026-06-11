# AI Pipeline v2 — Moments & Recap (Design)

**Date:** 2026-06-11
**Status:** Approved
**Scope:** Smart Moment Naming + Smart Summary (recap/progress headline) pipelines.

## Problem

The Apple Intelligence flows (smart moment save, recap) are slow, occasionally produce
truncated/odd text, and are sometimes refused by the model on fictional content
("Apple says it will not do it because of the content"). Audit of the current pipeline
(`AudioExtractionService` → `TranscriptionService` → `MomentNamingService` / `RecapService`)
found these root causes:

| # | Issue | Where | Effect |
|---|-------|-------|--------|
| 1 | `SFSpeechRecognizer(locale: Locale.current)` | TranscriptionService:24 | Book language ≠ device locale → garbage/empty transcript |
| 2 | No `requiresOnDeviceRecognition` | TranscriptionService:29 | Server recognition caps audio ~1 min; segments are 100–200 s; needs network |
| 3 | No `addsPunctuation = true` (default off) | TranscriptionService | Unpunctuated transcript → model invents punctuation → "verbatim quote" impossible, sentence post-processing degraded |
| 4 | Guardrail detection via `localizedDescription.contains("unsafe")` | PlayerViewModel:131 | Fragile, locale-dependent string match |
| 5 | Default guardrails | MomentNamingService, RecapService | False refusals on fiction (violence/romance) |
| 6 | No retry on transient errors | both services | `rateLimited` / model-warming failures surface to user |
| 7 | Speech auth denial silently kills smart save | PlayerViewModel | Permanent degradation; primary path shouldn't need permission at all |
| 8 | `quoteLine` never verified against transcript | MomentNamingService | "Verbatim" unenforced |
| 9 | Serial pipeline: export → transcribe → LLM | PlayerViewModel, AudiobookDetailViewModel | Latency stacks |
| 10 | `AVAssetExportPresetAppleM4A` re-encodes 100–200 s audio | AudioExtractionService | Slowest single step; avoidable on iOS 26 |
| 11 | No `LanguageModelSession.prewarm()` | both services | First-token latency paid on every save |
| 12 | Free-string mood/categories + `compactMap` drop | MomentNamingService | Invalid values silently lost |
| 13 | Default sampling | both services | Nondeterministic extraction output |

Key enabler: all AI surfaces already require iOS 26 (`@available(iOS 26, *)` + runtime
capability gate), so the iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` API is usable on
every device that can reach these code paths.

All API facts below were verified against the iOS 26.5 SDK swiftinterfaces
(`FoundationModels`, `Speech`).

## Goals

- **Fail very rarely** — eliminate locale, length-cap, punctuation, permission, and
  guardrail false-positive failure modes; retry transient errors.
- **Fast** — remove the export/re-encode step, use the fast file-transcription API,
  prewarm the language model, overlap pipeline stages.
- **Guided perfectly** — constrained decoding for enum-ish fields, deterministic
  sampling, verified-verbatim quotes, schema field order tuned for the ~4096-token
  shared budget.

Non-goals: streaming-only books gaining smart save (no local file — unchanged),
CarPlay voice search (separate `CarPlayVoiceSearch` path), iOS 18 behavior changes
(AI surfaces stay hidden there).

## Architecture

### 1. Transcription layer

New protocol (lives with the other service protocols, iOS-18-safe):

```swift
protocol SegmentTranscribing: Sendable {
    /// Transcribes [startSeconds, endSeconds] of the audio file. Never requires user permission.
    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String
}
```

**`SpeechAnalyzerTranscriptionService`** (`@available(iOS 26, *)`), the primary implementation:

- Opens `AVAudioFile(forReading:)`, seeks `framePosition` to `startSeconds`, reads
  PCM buffers covering the segment, yields them as an `AsyncStream<AnalyzerInput>` into
  `SpeechAnalyzer(modules: [transcriber]).analyzeSequence(_:)`; joins
  `transcriber.results` text. No export, no temp file, no re-encode, no length cap,
  no speech-recognition permission.
- `SpeechTranscriber(locale: locale, preset: .transcription)` (batch file transcription;
  punctuated output).
- Locale selection: prefer a `SpeechTranscriber.installedLocales` match for the device
  language; fall back to an English locale from `supportedLocales`. If assets are
  missing, run the one-time `AssetInventory.assetInstallationRequest(supporting:)`
  (bounded wait); on failure fall through to legacy.
- Any throw (unsupported locale, undecodable file, asset failure) → caller falls back
  to the **legacy path**.

**Legacy fallback** (hardened, kept for resilience):

- `AudioExtractionService` unchanged in role (export segment to temp m4a).
- `TranscriptionService` (SFSpeechRecognizer) hardened: `addsPunctuation = true`,
  `requiresOnDeviceRecognition = true` when `supportsOnDeviceRecognition`, locale kept
  but English fallback when current-locale recognizer is nil/unavailable.
- Speech authorization is requested **only** when the legacy path actually runs.

### 2. Generation layer (FoundationModels)

Both `MomentNamingService` and `RecapService`:

- **Model:** `SystemLanguageModel(guardrails: .permissiveContentTransformations)` —
  built for transforming user-provided content; fixes false refusals on fiction.
  Availability still checked via `SystemLanguageModel.default.isAvailable` (same
  underlying model).
- **Options:** `GenerationOptions(sampling: .greedy)` for deterministic extraction;
  `maximumResponseTokens` set with headroom (moments ~500, recap ~300).
- **Constrained decoding:** mood guided with `@Guide(.anyOf(MomentMood rawValues))`;
  categories guided with `.element(.anyOf(MomentCategory rawValues))` + `.count(1...3)`
  (both verified in the iOS 26.5 SDK). Invalid values become impossible instead of
  silently dropped; `compactMap`/`rawValue` parsing stays only as a final safety net.
- **Schema order preserved:** cheap structured fields first, `momentNote` last
  (budget-clip recovery via existing post-processing).
- **Typed error handling** in an iOS-26-gated mapper, surfaced through shared enums so
  iOS-18 callers/mocks need no availability gating:
  - `.guardrailViolation` / `.refusal` → `MomentNamingError.unsafeContent` /
    `RecapError.unsafeContent`
  - `.exceededContextWindowSize` → halve transcript (keep tail for moments, since most
    recent audio matters most), retry once
  - `.rateLimited` / `.concurrentRequests` → one retry after a short delay
  - everything else → mapped generation failure
- **Quote verification (moments):** normalize (case/diacritics/punctuation/whitespace)
  and fuzzy-match `quoteLine` against the transcript; snap to the matching transcript
  sentence so the stored quote is verbatim from the transcript; drop the quote if no
  match. Existing length/ratio sanitization retained behind this.
- **Prewarm:** `MomentAnalyzing` gains `prewarm()` (default no-op). iOS 26
  implementation creates the session up front, calls
  `LanguageModelSession.prewarm(promptPrefix:)`, caches the single prewarmed session
  for the next `analyzeMoment` call only (sessions are multi-turn; never reuse across
  two analyses).

### 3. ViewModel / flow changes

**`PlayerViewModel.performSmartSave`:**

- Drop the up-front speech-authorization gate; primary path needs none.
- Window changes from ±50 s to **75 s back / 15 s forward** of `currentTime` (the
  moment is what the user just heard; future audio is noise/spoilers and costs time).
- Stage overlap: kick `momentAnalyzer.prewarm()` as transcription starts.
- Unsafe detection: `catch MomentNamingError.unsafeContent` replaces the
  `localizedDescription` string match.
- All existing fallbacks preserved: any failure still lands in the manual moment sheet
  with `pendingMomentTime` set.

**`AudiobookDetailViewModel.loadRecap`:**

- Use `SegmentTranscribing` primary path (no auth), legacy fallback with auth.
- Same typed error mapping; friendlier `recapError` messages (map `unsafeContent` to
  honest copy about content checks; transient errors say "try again").
- Recap window stays 200 s back; anchor/persistence logic untouched.

**`PlayerView`:** `.onAppear` (and when `useSmartSave` flips true) calls
`viewModel.prewarmSmartSave()` so model load happens before the user taps.

**`AppleIntelligenceCapability.isSmartNamingAvailable`:** drop the hard
`SFSpeechRecognizer.isAvailable` requirement (primary path doesn't use it); model
availability is the gate. `unavailabilityReason` copy updated accordingly.

### 4. Protocol/DI wiring

- `SegmentTranscribing` joins the protocol folder with an `UnavailableSegmentTranscriber`
  (iOS 18 stub, throws) mirroring the existing pattern.
- `PlayerViewModel` / `AudiobookDetailViewModel` initializers gain
  `segmentTranscriber: (any SegmentTranscribing)? = nil` with the usual
  `if #available(iOS 26, *)` default branch.
- Existing `TranscriptionProviding` + `AudioExtracting` stay (legacy fallback path
  + mocks unchanged).

## Error handling summary

| Failure | Behavior |
|---------|----------|
| SpeechAnalyzer locale/asset/decode failure | Silent fallback to export + SFSpeechRecognizer |
| Legacy auth denied | Manual moment sheet (unchanged) |
| Empty transcript | Manual moment sheet / "Could not transcribe" (unchanged) |
| Guardrail/refusal | `unsafeContent` → existing warning UI, honest copy |
| Context window exceeded | Trim transcript, one retry |
| Rate limited / concurrent | One delayed retry |
| Model unavailable | Existing `.modelUnavailable` paths |

## Testing

- `MomentNamingServiceLogicTests` extended: quote fuzzy-match/snap/drop cases,
  transcript trimming helper, existing sentence-repair tests kept green.
- `RecapServiceLogicTests`: headline sanitize kept; error-mapping copy tests.
- VM tests: mock analyzer throwing `unsafeContent` → `pendingSmartSaveUnsafeWarning`;
  mock `SegmentTranscribing` (new mock in `PagelessTests/Mocks/`); fallback-ordering
  test (segment transcriber throws → legacy path used).
- In-memory containers per CLAUDE.md rules (`cloudKitDatabase: .none`, container held
  in a local).
- On-device pieces (`SpeechAnalyzer`, FoundationModels generation) are not unit-testable
  in CI; verified manually on the iPhone 15 Pro: smart save on a fiction book with a
  violent scene (refusal regression), recap, airplane-mode run (offline), non-English
  device-locale spot check.

## Expected outcome

- Smart save: ~10–25 s today → **~4–8 s** (no export, fast transcription, prewarmed model).
- Refusals on fiction: rare (permissive content-transformation guardrails).
- Truncation/odd fields: constrained decoding + greedy sampling + verified quotes +
  existing budget-aware post-processing.
- Permission prompts: gone from the primary path.
