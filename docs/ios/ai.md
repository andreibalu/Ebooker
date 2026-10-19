# Apple Intelligence

Read this before changing smart save, moment naming, transcription, recaps or welcome-back cards. AI is optional: every feature here sits behind a protocol in `Services/Protocols/`, and the app works fully without it.

## Gating

- `FoundationModels` and `SpeechAnalyzer` need iOS 26; the deployment target is lower. Real services (`MomentNamingService`, `RecapService`, `SpeechAnalyzerTranscriptionService`, `FoundationModelGeneration`) are `@available(iOS 26, *)`. View-model default initializers pick the real service or its `Unavailable…` stub with `if #available(iOS 26, *)`.
- Result, context and error types (`MomentAnalysis`, `AIPassageContext`, `MomentNamingError`, `RecapError`, `RecapGenerationResult`, `SegmentTranscriptionError`) live in the protocol files, which import only Foundation, so older-iOS callers and mocks need no gating.
- An AI surface renders only when all of these hold: `AppleIntelligenceCapability` (whose `isSmartNamingAvailable` checks model availability only, not speech recognition), Plus (`PlusEntitlementStore.shared.isPlus`, see `purchases.md`), the off-by-default `useLocalAIFeatures` setting, and the feature's own toggle. Copy an existing surface's gate (`PlayerView.useSmartSave`) when adding one.

## Transcription: two tiers

1. **Primary**: `SpeechAnalyzerTranscriptionService` reads the frame range straight from the audio file, with no export, temp file or length cap, and needs no speech-recognition permission. It may download speech assets on first use.
2. **Fallback**: `AudioExtractionService` exports a clip, then `TranscriptionService` runs `SFSpeechRecognizer` with punctuation. It requires on-device recognition and throws when the device lacks it; there is no server path. It tries the current locale, then `en-US`.

The fallback runs when the primary throws or returns an empty transcript. `CancellationError` is rethrown, never swallowed: a generic catch would open the speech permission prompt after the user cancelled.

Within smart save and recaps, the fallback is the only code that requests speech authorization. Keep authorization there; an up-front gate would block the permission-free primary path.

Windows differ by feature. For moments, the primary path and the fallback clip cover different spans (constants in `PlayerViewModel` and `AudioExtractionService`), so a fallback transcript is not the same text. Recaps use one window, ending at the saved position, on both paths (set inline in `AudiobookDetailViewModel.loadRecap`).

## Generation

- **Text only.** Every request goes through `FoundationModelGeneration.respond` on one shared `SystemLanguageModel(guardrails: .permissiveContentTransformations)`. The permissive guardrails cover `String` responses only (the SDK doc comment says so). Guided `@Generable` output keeps the default guardrails, which rejected about half of ordinary fiction passages, calm ones included, as `guardrailViolation`. So the services ask for labeled lines (`Title: …`) and parse them. Don't reintroduce `@Generable` for transcript content.
- **Parsing** lives in Foundation-only types that compile on every iOS version: `AIResponseText` (labeled fields, lists, titles, refusals, prose repair, transcript cleanup) and `MomentAnalysisParser` (moment reply format, vocabularies, quotes). The reply format for moments is built from `MomentMood` and `MomentCategory`, so a new case reaches the prompt and the parser together. Values the enums don't know are dropped.
- **Prompt framing.** Instructions say the passage is published literature the listener owns, that books depict mature themes, and to describe it neutrally like a study guide. The prompt header names book, author and chapter (`AIPassageContext`). Measured on the on-device model, two choices matter: the moment note comes before the tags (the model describes first, then tags more accurately), and category choices are listed alphabetically, because the small model copies list order. The model also drops the label of a prose line, so the parser sends unlabeled lines to an overflow field (`Note`, `Recap`).
- **Refusals.** Permissive mode never throws for text, but the model can still answer with a refusal sentence. `AIResponseText.isRefusal` catches it so it never becomes a name or a recap. A title is held to `isRefusalTitle`, which also needs refusal wording, because fiction titles open the same way ("I Won't Go Back"). A line ending in `:` that isn't a known label is a preamble and is dropped, so it can't claim the overflow field and push unlabeled prose into the title.
- **Failures and retries** (`FoundationModelGeneration.run`): a guardrail error, refusal or context overflow retries once on the second half of the passage; rate limits and concurrent requests retry once after a delay. iOS 27 reports a `resetDate`: the retry waits until it, and a reset further out than a few seconds fails at once, because a retry before the reset is rate limited again and the user is waiting on a spinner (`rateLimitDelay`); an unreadable reply or unsupported request fails at once, since greedy sampling would repeat it. iOS 27's `LanguageModelError` maps the same way. Callers match on `MomentNamingError` / `RecapError` (`.declined`, `.generationFailed`), never on strings. A failed session is never reused.
- **Greedy sampling** and a `maximumResponseTokens` cap keep output deterministic and latency bounded. The cap can still cut prose: `AIResponseText.trimToCompleteSentences` repairs notes and recaps, `MomentAnalysisParser.sanitizedQuoteLine` the quote, and `AIResponseText.cleanTitle` cuts an over-long title just before the last joiner that fits, so it never ends mid-phrase ("Bingley's arrival and Jane's" becomes "Bingley's arrival"). The model overshoots the headline's word count on about one in ten passages. A passage that opens mid-sentence can make the model start its recap or note in lowercase, so `AIResponseText.capitalizingFirstLetter` fixes the first letter.
- **Budget.** The context window is small and shared by instructions, prompt and reply. On iOS 27, `LanguageModelError.contextSizeExceeded` reports its size. `AIResponseText.cleanTranscript` collapses whitespace and drops a window's leading sentence fragment before the prompt.
- **Measuring.** Prompt or parser changes need a before/after run on the real model, on real fiction passages. The model a simulator uses is the host Mac's, so `tools/ai-harness/` compiles the app's AI sources into a macOS command-line tool that measures the same thing much faster than the simulator (its README has the commands). Quote the held-out passage set, not the tuned one: the prompts were tuned on the tuned set. The E2E opt-in test (`E2E_REAL_MODEL=1`, `e2e/README.md`) then confirms the in-app path. Use a simulator runtime of the host's major version: on a macOS 27 host, an iOS 26 simulator reports the model available but fails every request (its model catalog finds no assets), so a run there only exercises the fallback.

## Smart-save fallback

Smart save always opens the sheet with a usable name. When transcription or generation fails for any reason but cancellation, or the book isn't downloaded (transcription reads the local file), `MomentFallbackNamer` names the moment from the transcript's most mentioned character and the chapter ("Elizabeth in Chapter 34"), or chapter and time, or time alone. It fills only characters; note, quote, mood and categories stay empty and the draft isn't marked AI generated. The transcript is kept so moment search finds it. A calm `SmartSaveNotice` says why the name is simpler (not downloaded, couldn't transcribe, couldn't summarize). Never word it as an "unsafe content" warning: the passages are ordinary books.

Names come from `NLTagger` person names. Its name model is a downloadable language asset that simulators lack, so `MomentFallbackNamer.capitalizedNames` stands in when the tagger finds no person. Places and days are capitalized mid-sentence too, so that path drops weekdays, months, places the tagger did find, and words that look like a place once ("in London", "Baker Street"). Otherwise a first-person passage, which has no names, gets "London in Chapter 3".

## Prewarm

`MomentAnalyzing.prewarm()` and `RecapProviding.prewarm()` (default no-ops) load the model before the first request. `PlayerView` calls `prewarmSmartSave()` on appear while smart save is on and again when it turns on; both view models also prewarm right before transcription so loading overlaps it. `PrewarmedSessions` holds one session per feature, and each serves exactly one request: sessions are multi-turn, so a reused session would carry the previous passage's context. Recaps use one set of instructions with or without a headline, so either caller can use the prewarmed session.

## Welcome-back recaps

A card above the book-detail playback controls, for a downloaded, unfinished book left idle for days with enough saved progress. Thresholds live in `WelcomeBackRecapViewModel`. It needs the local-AI gate, Plus and the default-on `AISettingsKey.welcomeBackRecaps` setting.

- Passive: a failed generation hides the card and never asks for speech permission.
- Dismissal is device-local, stored per book against the last listening date, so new listening brings the card back.
- Generation writes the book's stored progress recap, which the detail screen's recap also reads.
- A cached recap is reused only when its anchor is at or slightly behind the saved position, never ahead. The tolerance is `Audiobook.progressRecapTolerance`.
- E2E hooks for recaps (`-e2e-fake-recap`, `-e2e-transcript-file`, …) are listed in `e2e/README.md`.
