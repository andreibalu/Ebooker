# Apple Intelligence

Read this before changing smart save, moment naming, transcription, recaps or welcome-back cards. AI is optional: every feature here sits behind a protocol in `Services/Protocols/`, and the app works fully without it.

## Gating

- `FoundationModels` and `SpeechAnalyzer` need iOS 26; the deployment target is lower. Real services (`MomentNamingService`, `RecapService`, `SpeechAnalyzerTranscriptionService`, `FoundationModelGeneration`) are `@available(iOS 26, *)`. View-model default initializers pick the real service or its `Unavailable…` stub with `if #available(iOS 26, *)`.
- Result and error types (`MomentAnalysis`, `MomentNamingError`, `RecapError`, `RecapGenerationResult`, `SegmentTranscriptionError`) live in the protocol files, which import only Foundation, so older-iOS callers and mocks need no gating.
- An AI surface renders only when all of these hold: `AppleIntelligenceCapability` (whose `isSmartNamingAvailable` checks model availability only, not speech recognition), Plus (`PlusEntitlementStore.shared.isPlus`, see `purchases.md`), the off-by-default `useLocalAIFeatures` setting, and the feature's own toggle. Copy an existing surface's gate (`PlayerView.useSmartSave`) when adding one.

## Transcription: two tiers

1. **Primary**: `SpeechAnalyzerTranscriptionService` reads the frame range straight from the audio file, with no export, temp file or length cap, and needs no speech-recognition permission. It may download speech assets on first use.
2. **Fallback**: `AudioExtractionService` exports a clip, then `TranscriptionService` runs `SFSpeechRecognizer` with punctuation. It requires on-device recognition and throws when the device lacks it; there is no server path. It tries the current locale, then `en-US`.

The fallback runs when the primary throws or returns an empty transcript. `CancellationError` is rethrown, never swallowed: a generic catch would open the speech permission prompt after the user cancelled.

Within smart save and recaps, the fallback is the only code that requests speech authorization. Keep authorization there; an up-front gate would block the permission-free primary path.

Windows differ by feature. For moments, the primary path and the fallback clip cover different spans (constants in `PlayerViewModel` and `AudioExtractionService`), so a fallback transcript is not the same text. Recaps use one window, ending at the saved position, on both paths (set inline in `AudiobookDetailViewModel.loadRecap`).

## Generation

- Both services use `SystemLanguageModel(guardrails: .permissiveContentTransformations)`. Default guardrails flag ordinary fiction (violence, romance); the permissive mode is for transforming the user's own content.
- Greedy sampling and a `maximumResponseTokens` cap keep extraction deterministic and latency-bounded.
- `FoundationModelGeneration.run` classifies generation errors: guardrail or refusal → `unsafeContent` with no retry; context overflow → one retry on the transcript's tail; rate-limited or concurrent → one delayed retry. iOS 27's `LanguageModelError` gets the same mapping. Callers match on the error enums (`MomentNamingError.unsafeContent`, `RecapError.unsafeContent`), never on description strings.
- **Budget.** The on-device context window is small and shared by prompt and response. On iOS 27, `LanguageModelError.contextSizeExceeded` reports its size. In `@Generable` structs fields generate in declaration order and the last one is clipped when the budget runs out, so declare cheap structured fields first and the longest prose last (a recap's `progressHeadline` precedes `recap` for this reason).
- The model ignores word and sentence counts, and the response cap can cut prose mid-sentence. `MomentNamingService.trimToCompleteSentences` repairs the moment note and `sanitizedQuoteLine` the quote; the moment name and the recap body are only whitespace-trimmed, so a clipped recap shows as clipped. A new prose field needs the same repair.
- **Guide literals.** Mood and categories use `@Guide(.anyOf…)` constrained decoding. Macro arguments can't reference constants, so the values exist three times: the `@Guide` literals, `categoryGuideValues` / `moodGuideValues`, and `MomentEnums`. Change all three together. No test compares them, and a value the enums don't know is dropped silently.

## Quotes

`MomentNamingService.verifiedQuote` keeps a model quote only when the transcript contains it, compared with case, diacritics and punctuation folded. A near-miss snaps to the transcript sentence that covers most of the quote's words; anything else is dropped as fabricated. Thresholds are constants beside the function.

## Prewarm

`MomentAnalyzing.prewarm()` (default no-op) loads the model before the first analysis. `PlayerView` calls `prewarmSmartSave()` on appear while smart save is on, and again when it turns on. A `PrewarmedMomentSession` serves exactly one analysis: sessions are multi-turn, so a reused session would carry the previous moment's context.

## Welcome-back recaps

A card above the book-detail playback controls, for a downloaded, unfinished book left idle for days with enough saved progress. Thresholds live in `WelcomeBackRecapViewModel`. It needs the local-AI gate, Plus and the default-on `AISettingsKey.welcomeBackRecaps` setting.

- Passive: a failed generation hides the card and never asks for speech permission.
- Dismissal is device-local, stored per book against the last listening date, so new listening brings the card back.
- Generation writes the book's stored progress recap, which the detail screen's recap also reads.
- A cached recap is reused only when its anchor is at or slightly behind the saved position, never ahead. The tolerance is `Audiobook.progressRecapTolerance`.
- E2E hooks for recaps (`-e2e-fake-recap`, `-e2e-transcript-file`, …) are listed in `e2e/README.md`.
