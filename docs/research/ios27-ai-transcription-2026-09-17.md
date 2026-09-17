# iOS 27 AI transcription and generation research

**Research date:** 2026-09-17 (Europe/Bucharest)
**Product:** Unpaged (Xcode scheme `Pageless`)
**Scope:** Apple-first verification of iOS 27 Speech and Foundation Models APIs, the installed SDK, and bounded speed/cancellation improvements that are safe to consider for the existing iOS 18 deployment target.

## Decision

iOS 27 documentation is published and the local machine has Xcode 27.0 with the iOS 27.0 SDK. Apple documents changes to Foundation Models and Speech for the 27 platform releases, but there is no Apple documentation in the reviewed sources announcing a new iOS 27 transcription engine or a replacement for `SpeechAnalyzer`/`SpeechTranscriber`. Those remain iOS 26 APIs. The iOS 27 Speech additions are input and resource-management helpers, while the most consequential current-code change is the new typed Foundation Models error taxonomy.

The coordinator should dispatch one bounded Luna Max implementation pass with these acceptance criteria:

1. Update `FoundationModelGeneration.run` to preserve `CancellationError`, use a cancellation-aware retry delay, and map the iOS 27 `LanguageModelError` and `LanguageModelSession.Error` cases while retaining the iOS 26 path. Guard the iOS 27 catches with availability-safe code. Add focused tests proving that cancellation does not become `.failed`, no retry starts after cancellation, guardrail/refusal remains `.unsafeContent`, and context/rate-limit/concurrent-request behavior is bounded.
2. Migrate `GenerationOptions(sampling: ...)` to the documented `samplingMode:` spelling in `MomentNamingService` and `RecapService`. This is a source-compatibility cleanup with iOS 26 back deployment, not a model-behavior change.
3. Harden `SpeechAnalyzerTranscriptionService` cancellation and task ownership. A cancelled caller must cancel and await the feeder/results tasks, finish the input continuation, cancel/finish the analyzer, and propagate cancellation. Preserve audio ordering; do not add a lossy `AsyncStream` buffering policy merely to cap memory.
4. Add latency instrumentation before and after any model-retention/preparation change. A measured follow-up may use `SpeechAnalyzer.Options(priority:modelRetention: .lingering)`, `prepareToAnalyze(in:)`, and `LanguageModelSession.prewarm(promptPrefix:)`; all are documented existing APIs and should be accepted only if physical-device measurements show a useful first-result or total-latency improvement without unacceptable memory/thermal cost.

Do not dispatch an iOS 27-only Speech rewrite or Private Cloud Compute integration in this pass. `AssetInputSequenceProvider`, `AnalyzerInputConverter`, progressive transcription presets, and PCC are valid research targets, but their fit, range semantics, accuracy/latency trade-offs, entitlements, or privacy impact still need device evidence and product decisions. The existing custom feeder remains the compatibility path for iOS 26.

## What Apple has published

Apple’s [Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels) page for the 27 platform releases describes dynamic language-model profiles, the `LanguageModel` protocol, and improved typed errors: `LanguageModelError`, `SystemLanguageModel.Error`, and `LanguageModelSession.Error`. It also warns that the on-device model changes with an iOS 27 update and that prompts should be tested against the new model.

The [iOS and iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), [What’s new in iOS 27](https://developer.apple.com/ios/whats-new/), and [27 platform release documentation](https://developer.apple.com/documentation/updates) are live. Some pages and API topics are labelled beta, so “published” does not mean every item is final or safe to use without availability checks.

Apple’s [Speech updates](https://developer.apple.com/documentation/updates/speech) page documents `AssetInputSequenceProvider` and `CaptureInputSequenceProvider` for obtaining analyzer input, and `AnalyzerInputConverter` for converting audio buffers. The [Speech framework overview](https://developer.apple.com/documentation/speech/) and [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer) documentation describe the iOS 26 analyzer/module/result-stream design; they do not describe a new iOS 27 transcription model. The 27 release notes mention general Neural Engine and AI-model loading improvements, not a changed SpeechTranscriber model or an app-facing transcription accuracy guarantee.

## Installed SDK and project baseline

Read-only checks on 2026-09-17 reported:

```text
xcodebuild -version
Xcode 27.0
Build version 27A266a

xcrun --sdk iphoneos --show-sdk-version
27.0

xcodebuild -showsdks
iOS 27.0 -sdk iphoneos27.0
Simulator - iOS 27.0 -sdk iphonesimulator27.0
```

The inspected SDK paths are:

```text
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-ios.swiftinterface
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface
```

The project still has `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, Swift 5.0, and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in [`Pageless.xcodeproj/project.pbxproj`](../../Pageless.xcodeproj/project.pbxproj). No production source, project setting, or test was changed by this research. No build or device test was claimed; the coordinator notes that device MCP access is unavailable.

The iOS 27 interfaces confirm the following compile-time facts:

| API | SDK availability observed | Assessment |
| --- | --- | --- |
| `SpeechAnalyzer`, `SpeechTranscriber`, `bestAvailableAudioFormat`, direct file initializer, `prepareToAnalyze(in:)` | iOS 26 | Existing direct analyzer path is still valid on iOS 26 and 27. |
| `SpeechAnalyzer.Options.ModelRetention.lingering` and `.processLifetime` | iOS 26 | A documented cache choice; retention cost needs measurement. |
| `SpeechAnalyzer.Options.ignoresResourceLimits` | iOS 27 | Beta/explicitly risky for production; not warranted for one foreground operation. |
| `AssetInputSequenceProvider`, `AnalyzerInputConverter`, `CMReadySampleBuffer` input | iOS 27 | Confirmed symbols, but not proven to preserve this service’s arbitrary frame-range behavior or improve end-to-end latency. |
| `LanguageModelError` and new `LanguageModelSession.Error` cases | iOS 27 | Confirmed replacement/error refinement that the shared generation helper should map. |
| `GenerationOptions(samplingMode:)` | iOS 26 and back-deployed in the Xcode 27 interface; `sampling:` deprecated at iOS 27 | Safe spelling migration while keeping iOS 26 behavior. |
| `LanguageModelSession.prewarm(promptPrefix:)` | iOS 26 | Confirmed advisory optimization; current code calls the no-prefix form. |
| `PrivateCloudComputeLanguageModel` | iOS 27 | Confirmed, but network/entitlement/quota/privacy scope makes it future-only for Unpaged. |

## Existing implementation and observed risks

### Direct SpeechAnalyzer transcription

[`SpeechAnalyzerTranscriptionService`](../../Pageless/Services/SpeechAnalyzerTranscriptionService.swift#L10) creates a `SpeechTranscriber(locale:preset: .transcription)`, installs missing assets, opens the original `AVAudioFile`, seeks to the requested frame range, converts chunks to the analyzer format, and feeds an `AsyncStream<AnalyzerInput>`. This matches Apple’s documented module/result-stream model and keeps the intended properties: no export, no temporary file, no speech-recognition permission, and no legacy length cap. [`SegmentTranscribing`](../../Pageless/Services/Protocols/SegmentTranscribing.swift#L21) correctly documents fallback to the legacy path on failure.

The service currently creates an unbounded `AsyncStream` at line 51 and ignores the `YieldResult` at line 162. The detached feeder can therefore read and retain input buffers faster than the analyzer consumes them. Switching to `.bufferingNewest` or `.bufferingOldest` would bound memory by dropping audio; dropped audio is unacceptable for a transcript and can silently damage quote verification and recap context. A non-lossy bounded channel could be designed, but it is a larger concurrency change than this research should authorize.

The operation also creates an unstructured feeder task and results task without a parent cancellation handler. The error branch cancels both tasks but does not await them or explicitly finish the input continuation. If the caller task is cancelled while `analyzeSequence` or the feeder is active, the current catch maps cancellation to `SegmentTranscriptionError.analysisFailed`, and task/stream teardown is not guaranteed to complete promptly. This is a bounded lifecycle defect worth fixing now; it is independent of an iOS 27 model claim.

Apple documents that analyzer input, output result streams, and finishing are separate controls in [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer), that analyzer errors are delivered to waiting methods/result streams, and that ending the input sequence does not generally finish analysis by itself. That supports an explicit cancellation handler and an awaited teardown sequence. It does not support silently dropping buffers to create backpressure.

The current locale resolver checks installed locales, then supported locales, then chooses same-language or English. Apple also exposes [`SpeechTranscriber.supportedLocale(equivalentTo:)`](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocale%28equivalentto%3A%29), which can simplify locale matching. This is a correctness/maintenance cleanup, not a demonstrated speedup, and should remain secondary to cancellation.

### Foundation Models generation

[`FoundationModelGeneration`](../../Pageless/Services/FoundationModelGeneration.swift#L9) currently catches only the deprecated-on-iOS-27 `LanguageModelSession.GenerationError`. Its retry policy maps guardrail/refusal to `.unsafeContent`, retries context overflow with the transcript tail, and retries rate-limit/concurrent-request failures after 700 ms. The delay is `try? await Task.sleep`, so cancellation is swallowed; the outer generic catches then turn cancellation into `.failed`. On iOS 27, the new typed errors can also fall through that generic catch, losing the intended distinction between unsafe content, context overflow, transient rate limiting, and ordinary failure.

Apple’s [`LanguageModelError`](https://developer.apple.com/documentation/foundationmodels/languagemodelerror) documents `contextSizeExceeded`, `rateLimited`, `guardrailViolation`, `refusal`, `timeout`, unsupported-content/guide/locale cases, and related errors. The iOS 27 SDK interface marks the old `GenerationError` cases as deprecated and points them to the new `LanguageModelError`, `SystemLanguageModel.Error`, or `LanguageModelSession.Error` types. This is confirmed SDK evidence, not a forecast.

The fix should be narrow: retain the iOS 26 mapping, add an availability-gated iOS 27 mapping helper, rethrow cancellation before generic failure mapping, check cancellation before retry, and use a throwing sleep. No new retry count or unbounded delay is justified. A fresh session per attempt remains correct because Apple’s [`LanguageModelSession`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) accumulates transcript context.

Both [`MomentNamingService`](../../Pageless/Services/MomentNamingService.swift#L11) and [`RecapService`](../../Pageless/Services/RecapService.swift#L9) use `SystemLanguageModel(guardrails: .permissiveContentTransformations)` and greedy generation with a token cap. The moment service already prewarms one session, but calls the no-prefix [`prewarm`](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm%28promptprefix%3A%29) form. Apple says a prompt prefix can cache predictable work and should be used when there is a strong signal the session will be used shortly; prewarm is advisory and does not guarantee immediate loading. The current moment prompt prefix and the recap prompt prefix are stable enough to measure this optimization. Any prewarmed session must remain single-use because these sessions are multi-turn.

The existing `GenerationOptions(sampling:)` calls are deprecated in the Xcode 27 SDK. Apple’s [`GenerationOptions`](https://developer.apple.com/documentation/foundationmodels/generationoptions) documents `samplingMode:` and cautions that a strict output cap can produce malformed or incomplete output. Keep the existing caps and post-processing; migrate only the spelling first, then measure before changing token budgets.

Apple’s [context-window guidance](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window) says the on-device model context is 4096 tokens and counts instructions, prompt, schema, tools, and output. The current tail retry and structured-field ordering are therefore still appropriate. A larger context is not evidence that Unpaged should send more audiobook text.

### Capability and compatibility boundaries

[`AppleIntelligenceCapability`](../../Pageless/Services/AppleIntelligenceCapability.swift#L1) checks `SystemLanguageModel.default.isAvailable` under `#available(iOS 26, *)`, and the ViewModels choose unavailable protocol stubs below iOS 26. This preserves the project’s iOS 18 deployment target. Do not move Foundation Models types into shared iOS 18-visible declarations or add an unconditional permission gate.

## Changes worth implementing now

### 1. Make generation cancellation and typed failures correct

Implement this first because it improves responsiveness and error fidelity on both iOS 26 and 27 without changing the user-facing model choice.

- Add a cancellation check before the first attempt, before any retry, and after the retry delay.
- Let `CancellationError` pass through from the attempt and from `Task.sleep`; it must not become `FoundationModelGeneration.Failure.failed`, `MomentNamingError.generationFailed`, or `RecapError.generationFailed`.
- Keep the existing one-retry limit and transcript-tail behavior.
- On iOS 27, map guardrail/refusal to `.unsafeContent`, context overflow to the tail retry, rate limit and concurrent requests to the bounded delayed retry, and timeout/unsupported/asset/transcript-mutation failures to `.failed` unless a later product decision adds a specific user state.
- Keep iOS 26 `GenerationError` handling in an availability-safe path. Do not remove support for the iOS 26 runtime merely because Xcode 27 is installed.
- Add tests around the policy rather than tests that invoke Apple Intelligence. An injectable attempt closure is sufficient for cancellation, retry count, and typed-policy tests.

### 2. Migrate the options spelling

Change both services to `GenerationOptions(samplingMode: .greedy, maximumResponseTokens: ...)`. The Xcode 27 interface marks the old spelling deprecated and back-deploys the new spelling for the supported older runtime. Keep greedy sampling, field ordering, quote verification, sentence trimming, and current token caps until a device benchmark shows a reason to change them.

### 3. Close the SpeechAnalyzer cancellation hole

Wrap the analyzer/feed/results lifecycle in a cancellation handler. Cancellation must finish the input stream, cancel the feeder and results task, cancel/finish the analyzer through the documented API, await both child results, and rethrow cancellation. The normal-success path must still feed the complete range before finalization, and analyzer/feed errors must still become the existing typed fallback error.

Do not use a dropping `AsyncStream` policy. If memory measurements show that the feeder outruns the analyzer, prototype a non-lossy bounded channel with explicit producer suspension, or test Apple’s iOS 27 asset provider. Neither should be merged from source inspection alone.

### 4. Measure documented preparation and retention

The implementation agent may put `SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)` and `prepareToAnalyze(in:)` behind the existing iOS 26 availability boundary. Apple documents lingering retention as keeping compatible model resources available for reuse and `prepareToAnalyze` as proactively loading resources. Treat both as experiments:

- record first-input/first-result and final-result latency;
- record peak memory, thermal state, and battery impact;
- test consecutive smart-save and recap operations, asset-install waits, locale changes, and cancellation;
- retain the change only if it improves the physical-device result without changing transcript text or fallback behavior.

For Foundation Models, change the moment prewarm to use the exact stable prompt prefix only after confirming the prewarm task has at least one second before the user action. A future optional `prewarm()` on `RecapProviding` could mirror the moment path, but it is an API-surface change and should follow a measured need rather than being assumed to help.

## Future or experimental work

| Candidate | Confirmed fact | Why it stays future-only |
| --- | --- | --- |
| `AssetInputSequenceProvider` + `AnalyzerInputConverter` | Apple documents them in the Speech updates and iOS 27 SDK. | The current service transcribes an arbitrary frame range. The provider docs describe asset/track input, but this research did not establish exact range trimming, converter flush behavior, or end-to-end accuracy/latency. Keep the custom iOS 26 feeder until a physical iOS 27 spike proves equivalence. |
| Progressive/time-indexed SpeechTranscriber presets | [`SpeechTranscriber.Preset`](https://developer.apple.com/documentation/speech/speechtranscriber/preset) documents fast/volatile result variants. | The current workflow needs a final transcript for quote verification and AI generation. Earlier partial results may improve perceived latency but can reduce accuracy or require a new incremental state model. Benchmark before changing `.transcription`. |
| Direct `SpeechAnalyzer(inputAudioFile: ...)` | Apple documents a convenience initializer. | It does not by itself prove arbitrary segment-range semantics or preserve the current no-export range contract. |
| `ignoresResourceLimits` | Confirmed iOS 27 option. | Apple warns that unlimited concurrent resource use may fail unpredictably. Unpaged has one foreground operation and does not need this escape hatch. |
| `PrivateCloudComputeLanguageModel` | Apple documents an iOS 27 model with larger context and stronger reasoning. | It needs network access, a private-cloud-compute entitlement, quota handling, and a new product/privacy decision. Apple’s [PCC documentation](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) recommends starting with on-device intelligence. It is not a faster drop-in replacement for current offline recaps/moments. |
| `ContextOptions.reasoningLevel`, dynamic profiles, multimodal prompts, or adopting `LanguageModel` | Confirmed in the iOS 27 Foundation Models documentation/SDK. | Current features are short, structured, on-device text transformations. These APIs add model-capability and prompt/product decisions without evidence that they improve Unpaged’s moment/recap path. |

## iOS compatibility, permissions, and privacy

| Runtime | Required behavior |
| --- | --- |
| iOS 18 | Keep `UnavailableSegmentTranscriber`, `UnavailableMomentAnalyzer`, and `UnavailableRecapProvider`. AI surfaces stay hidden through the existing capability checks. No Foundation Models or SpeechAnalyzer symbol may be referenced outside availability-safe declarations/branches. |
| iOS 26 | Keep the current SpeechAnalyzer range path and on-device `SystemLanguageModel`. The cancellation fix, `samplingMode:`, prewarm, `prepareToAnalyze`, and lingering retention are compatible candidates, subject to tests. The legacy SFSpeechRecognizer fallback remains available. |
| iOS 27 | Add typed error mapping. Test prompt behavior against the updated on-device model. Consider iOS 27 Speech input helpers only after the range/accuracy/latency spike. |

Apple’s [speech permission guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition) distinguishes `SFSpeechRecognizer` from SpeechAnalyzer transcriber modules: the latter do not send the user’s voice audio to Apple servers and do not require the speech-recognition permission. The current app’s primary path therefore must continue to avoid an up-front speech authorization request. The fallback still needs `NSSpeechRecognitionUsageDescription` and user authorization; preserve its delayed, failure-only request and existing privacy documentation.

The Speech asset installation request is system-managed model data, not a reason to introduce a new app permission. Any user-visible change that adds network behavior, PCC, or a new data flow would require the repository’s support/privacy/EULA review described by `AGENTS.md`; this research proposes no such product change. Foundation Models’ on-device path remains the appropriate privacy boundary. Apple’s Foundation Models Instruments guidance also warns that performance traces can contain prompts and responses; keep any trace local and treat audiobook text as sensitive.

## Validation required before calling the work complete

1. Build the app and tests with Xcode 27 while retaining the iOS 18 deployment target. Confirm availability checking and no accidental Foundation Models/Speech 27 references in iOS 18-visible code.
2. Unit-test `FoundationModelGeneration` policy with an injected attempt closure: first-attempt success, context-tail retry, rate-limit/concurrent retry, unsafe content, ordinary failure, cancellation during attempt, cancellation before retry, and cancellation during retry sleep. Verify the attempt count and exact propagated error.
3. Test the Speech service with invalid ranges/audio, analyzer failure, empty result, caller cancellation during feeding, caller cancellation while awaiting results, and normal finalization. Verify no hang, no task leak, no dropped input, and correct fallback classification.
4. On a physical Apple Intelligence-capable iPhone 15 Pro running iOS 27, compare baseline versus each preparation/retention/prewarm change using representative synthetic or approved private clips. Record first input, first result, final result, total wall time, peak memory, thermal/battery observations, transcript accuracy, quote verification, moment fields, and recap completeness. Simulator evidence cannot qualify Apple Intelligence behavior here.
5. Repeat the fallback permission matrix on iOS 18/26: primary SpeechAnalyzer does not request speech authorization; a forced primary failure requests authorization only for the legacy path; denied/restricted states remain recoverable.
6. If the iOS 27 asset-provider spike proceeds, verify arbitrary segment boundaries, `AnalyzerInputConverter.flush()` before analyzer finalization, locale/asset installation, cancellation, and parity with the iOS 26 feeder. Do not remove the fallback until that evidence exists.
7. Record representative iOS 26 outputs, compare them with iOS 27 outputs, and recheck prompt instructions, quote verification, categories/mood, sentence trimming, and headline clipping. Apple’s [prompt-update guidance](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions) specifically recommends testing when the on-device model changes.

## Implementation handoff

The subsequent Luna Max implementation pass added availability-gated iOS 27 error mapping while retaining the iOS 26 policy, migrated both generation services to `samplingMode:`, preserved cancellation through generation and transcription callers, and added explicit SpeechAnalyzer cancellation teardown. Regression tests were written for cancellation, retry policy, and legacy-fallback suppression. No model-retention, prewarm, new Speech input-provider, or Private Cloud Compute experiment was enabled.

Coordinator verification: Swift syntax parsing, StoreKit JSON validation, and `git diff --check` passed. This is static evidence only. Device build/test tools were unavailable in this session, so compilation, test execution, physical-device teardown behavior, StoreKit purchase behavior, and latency benchmarks remain pending. No speedup is claimed.

## Primary Apple sources

- [Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels)
- [iOS and iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
- [What’s new in iOS 27](https://developer.apple.com/ios/whats-new/)
- [27 platform release documentation](https://developer.apple.com/documentation/updates)
- [Speech updates](https://developer.apple.com/documentation/updates/speech)
- [Speech framework](https://developer.apple.com/documentation/speech/)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [SpeechTranscriber.Preset](https://developer.apple.com/documentation/speech/speechtranscriber/preset)
- [AssetInputSequenceProvider](https://developer.apple.com/documentation/speech/assetinputsequenceprovider)
- [AnalyzerInputConverter.convert(_:at:)](https://developer.apple.com/documentation/speech/analyzerinputconverter/convert%28_%3Aat%3A%29)
- [SpeechTranscriber.supportedLocale(equivalentTo:)](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocale%28equivalentto%3A%29)
- [SpeechModels](https://developer.apple.com/documentation/speech/speechmodels)
- [Asking permission to use speech recognition](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
- [LanguageModelSession.prewarm(promptPrefix:)](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm%28promptprefix%3A%29)
- [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror)
- [GenerationOptions](https://developer.apple.com/documentation/foundationmodels/generationoptions)
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)
- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)
