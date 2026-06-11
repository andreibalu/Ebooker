# AI Pipeline v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Smart Moment Naming and Smart Summary fast, near-failure-free, and perfectly guided: iOS 26 `SpeechAnalyzer` transcription (no export, no permission, punctuated), permissive content-transformation guardrails (fixes refusals on fiction), constrained decoding for mood/categories, typed error handling with retry, prewarmed model, verified-verbatim quotes.

**Spec:** `docs/superpowers/specs/2026-06-11-ai-pipeline-v2-design.md` — read it first.

**Architecture:** New `SegmentTranscribing` protocol with an iOS 26 `SpeechAnalyzerTranscriptionService` primary implementation; the existing export + `SFSpeechRecognizer` pipeline becomes a hardened fallback. Both `MomentNamingService` and `RecapService` move to `SystemLanguageModel(guardrails: .permissiveContentTransformations)` with greedy sampling, guide-constrained fields, and a shared typed-error/retry helper. ViewModels get small, separately testable pipeline functions.

**Tech Stack:** Swift / SwiftUI, FoundationModels (iOS 26), Speech `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26), AVFoundation, Swift Testing.

**Verified API facts (iOS 26.5 SDK swiftinterfaces — do not re-derive):**
- `SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)` — guardrails are set on the **model**, not the session.
- `LanguageModelSession.GenerationError` cases: `.exceededContextWindowSize`, `.assetsUnavailable`, `.guardrailViolation`, `.unsupportedLanguageOrLocale`, `.decodingFailure`, `.rateLimited`, `.concurrentRequests`, `.refusal(Refusal, Context)` (all others carry one `Context`).
- `LanguageModelSession.prewarm(promptPrefix: Prompt? = nil)`.
- `GenerationOptions(sampling: .greedy, temperature: nil, maximumResponseTokens: Int?)`.
- `@Guide(description: String? = nil, _ guides: GenerationGuide<T>...)`; `GenerationGuide.anyOf([String])`, `.count(1...3)`, `.element(innerGuide)`, `.maximumCount(n)`.
- `SpeechTranscriber(locale:preset:)` with `Preset.transcription`; `SpeechTranscriber.supportedLocales` / `.installedLocales` are `static var ... { get async }`.
- `SpeechAnalyzer(modules:)` is an actor; `analyzeSequence(_ inputSequence:)` consumes `AsyncSequence<AnalyzerInput>`; `finalizeAndFinishThroughEndOfInput()`.
- `AnalyzerInput(buffer: AVAudioPCMBuffer)`; `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:considering:)`.
- `AssetInventory.assetInstallationRequest(supporting: [module])` returns optional `AssetInstallationRequest`; `downloadAndInstall() async throws`.

**Project rules (from CLAUDE.md):**
- Build/test via XcodeBuildMCP only (scheme `Pageless`, Andrei's iPhone 15 Pro `00008130-000471A80C81001C`). Tests: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`. Never run `xcodebuild` from the terminal.
- The Xcode project uses filesystem-synchronized groups — new files under `Pageless/` and `PagelessTests/` join their targets automatically; no pbxproj editing.
- Never reference `FoundationModels` symbols outside an `@available(iOS 26, *)` type or `if #available` block. Shared types/errors live in the protocol files so iOS-18 callers and mocks need no gating.
- Commit messages: Conventional Commits; append `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` as the final line of every commit body.

**File map:**

| File | Action | Responsibility |
|------|--------|----------------|
| `Pageless/Services/Protocols/MomentAnalyzing.swift` | Modify | + `unsafeContent`/`generationFailed` cases, `prewarm()` requirement w/ default |
| `Pageless/Services/Protocols/RecapProviding.swift` | Modify | + `unsafeContent`/`generationFailed` cases |
| `Pageless/Services/Protocols/SegmentTranscribing.swift` | Create | New protocol + error enum + iOS 18 stub |
| `Pageless/Services/FoundationModelGeneration.swift` | Create | Shared typed-error mapping + single retry |
| `Pageless/Services/MomentNamingService.swift` | Modify | Guardrails, guides, greedy, retry, prewarm, verified quotes |
| `Pageless/Services/RecapService.swift` | Modify | Guardrails, guides, greedy, retry, headline-first field order |
| `Pageless/Services/SpeechAnalyzerTranscriptionService.swift` | Create | iOS 26 segment transcription |
| `Pageless/Services/TranscriptionService.swift` | Modify | Punctuation, on-device, locale fallback |
| `Pageless/Services/AppleIntelligenceCapability.swift` | Modify | Drop hard SFSpeech requirement |
| `Pageless/ViewModels/PlayerViewModel.swift` | Modify | New transcript pipeline, typed unsafe catch, prewarm |
| `Pageless/ViewModels/AudiobookDetailViewModel.swift` | Modify | New transcript pipeline, friendly error copy |
| `Pageless/Views/PlayerView.swift` | Modify | Prewarm hook |
| `PagelessTests/Mocks/MockSegmentTranscriber.swift` | Create | Mock for new protocol |
| `PagelessTests/Mocks/MockTranscriptionService.swift` | Modify | Call counters |
| `PagelessTests/Mocks/MockMomentAnalyzer.swift` | Modify | `errorToThrow` |
| `PagelessTests/Mocks/MockRecapService.swift` | Modify | `errorToThrow` |
| `PagelessTests/ServiceTests/MomentNamingServiceLogicTests.swift` | Modify | Quote verification + guide-sync tests |
| `PagelessTests/ViewModelTests/PlayerViewModelTests.swift` | Modify | Pipeline tests |
| `PagelessTests/ViewModelTests/AudiobookDetailViewModelTests.swift` | Modify | Pipeline tests |

---

### Task 1: Shared error types + protocol additions

**Files:**
- Modify: `Pageless/Services/Protocols/MomentAnalyzing.swift`
- Modify: `Pageless/Services/Protocols/RecapProviding.swift`

- [x] **Step 1.1: Extend `MomentNamingError` and add `prewarm()` to `MomentAnalyzing`**

Replace the `MomentNamingError` enum and the protocol in `Pageless/Services/Protocols/MomentAnalyzing.swift`:

```swift
enum MomentNamingError: LocalizedError, Equatable {
    case modelUnavailable
    /// The on-device model declined the content (guardrail or refusal).
    case unsafeContent
    /// Generation failed after retry (transient model error, decoding failure, …).
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .unsafeContent:
            "Apple Intelligence declined to analyze this passage."
        case .generationFailed:
            "Couldn't analyze this moment."
        }
    }
}

protocol MomentAnalyzing: Sendable {
    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis

    /// Optional: load model resources ahead of the first `analyzeMoment` call.
    func prewarm()
}

extension MomentAnalyzing {
    func prewarm() {}
}
```

Leave `MomentAnalysis` and `UnavailableMomentAnalyzer` untouched (the stub inherits the no-op `prewarm()`).

- [x] **Step 1.2: Extend `RecapError`**

In `Pageless/Services/Protocols/RecapProviding.swift`, replace the `RecapError` enum:

```swift
enum RecapError: LocalizedError, Equatable {
    case modelUnavailable
    case noAudioAvailable
    /// The on-device model declined the content (guardrail or refusal).
    case unsafeContent
    /// Generation failed after retry (transient model error, decoding failure, …).
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Apple Intelligence is not available."
        case .noAudioAvailable:
            "No audio available for recap."
        case .unsafeContent:
            "Apple Intelligence declined to summarize this passage."
        case .generationFailed:
            "Couldn't generate a recap. Please try again."
        }
    }
}
```

- [x] **Step 1.3: Build**

Run: `mcp__XcodeBuildMCP__build_device` (scheme `Pageless`).
Expected: BUILD SUCCEEDED.

- [x] **Step 1.4: Commit**

```bash
git add Pageless/Services/Protocols/MomentAnalyzing.swift Pageless/Services/Protocols/RecapProviding.swift
git commit -m "feat(ai): typed unsafe/failed errors + analyzer prewarm hook"
```

---

### Task 2: Verified-verbatim quotes (TDD)

**Files:**
- Modify: `Pageless/Services/MomentNamingService.swift`
- Test: `PagelessTests/ServiceTests/MomentNamingServiceLogicTests.swift`

- [x] **Step 2.1: Write failing tests**

Append inside `MomentNamingServiceLogicTests` (follow the file's existing `guard #available(iOS 26, *)` pattern):

```swift
// MARK: - verifiedQuote

@Test func verifiedQuoteKeepsQuotePresentInTranscript() {
    guard #available(iOS 26, *) else { return }
    let service = MomentNamingService()
    let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
    let out = service.verifiedQuote("The storm broke over the harbor at midnight, and nobody slept.", transcript: transcript)
    #expect(out == "The storm broke over the harbor at midnight, and nobody slept.")
}

@Test func verifiedQuoteIsCaseAndPunctuationInsensitive() {
    guard #available(iOS 26, *) else { return }
    let service = MomentNamingService()
    let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
    let out = service.verifiedQuote("the storm broke over the harbor at midnight and nobody slept.", transcript: transcript)
    #expect(!out.isEmpty)
}

@Test func verifiedQuoteSnapsParaphraseToTranscriptSentence() {
    guard #available(iOS 26, *) else { return }
    let service = MomentNamingService()
    let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
    // Model dropped words — most of the words still come from one transcript sentence.
    let out = service.verifiedQuote("Storm broke over harbor at midnight, nobody slept!", transcript: transcript)
    #expect(out == "The storm broke over the harbor at midnight, and nobody slept.")
}

@Test func verifiedQuoteDropsFabricatedQuote() {
    guard #available(iOS 26, *) else { return }
    let service = MomentNamingService()
    let transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept."
    let out = service.verifiedQuote("To be or not to be, that is the question.", transcript: transcript)
    #expect(out.isEmpty)
}

@Test func verifiedQuoteDropsVeryShortNonVerbatimQuote() {
    guard #available(iOS 26, *) else { return }
    let service = MomentNamingService()
    let transcript = "The storm broke over the harbor at midnight, and nobody slept."
    let out = service.verifiedQuote("Harbor explosions!", transcript: transcript)
    #expect(out.isEmpty)
}

// MARK: - matchKey / sentences

@Test func matchKeyFoldsCasePunctuationAndDiacritics() {
    guard #available(iOS 26, *) else { return }
    #expect(MomentNamingService.matchKey("Café—NIGHT, falls!") == "cafe night falls")
}

@Test func sentencesSplitsOnTerminators() {
    guard #available(iOS 26, *) else { return }
    let out = MomentNamingService.sentences(in: "One came first. Two came second! Three came third?")
    #expect(out == ["One came first.", "Two came second!", "Three came third?"])
}
```

- [x] **Step 2.2: Run tests, verify the new ones fail to compile/fail**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: compile error — `verifiedQuote` does not exist yet. That is the failing state.

- [x] **Step 2.3: Implement in `MomentNamingService`**

Add to `MomentNamingService` (below `sanitizedQuoteLine`):

```swift
/// Sanitizes the model's quote, then guarantees it is verbatim from the transcript:
/// keeps it when the transcript contains it (ignoring case/punctuation/diacritics),
/// snaps near-misses to the best-matching transcript sentence, drops fabrications.
func verifiedQuote(_ rawQuote: String, transcript: String) -> String {
    let sanitized = sanitizedQuoteLine(rawQuote, transcript: transcript)
    guard !sanitized.isEmpty else { return "" }
    let quoteKey = Self.matchKey(sanitized)
    guard !quoteKey.isEmpty else { return "" }

    if Self.matchKey(transcript).contains(quoteKey) {
        return sanitized
    }
    return Self.bestMatchingSentence(for: sanitized, in: transcript) ?? ""
}

/// Lowercased, diacritic-folded, punctuation-stripped, whitespace-collapsed form
/// used for verbatim comparison.
static func matchKey(_ text: String) -> String {
    let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    let mapped = folded.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }
    return String(mapped).split(separator: " ").joined(separator: " ")
}

static func sentences(in text: String) -> [String] {
    var result: [String] = []
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
        if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
            result.append(sentence)
        }
    }
    return result
}

/// Transcript sentence sharing ≥ 70% of the quote's words; nil when the quote has
/// fewer than 3 words or nothing in the transcript comes close.
static func bestMatchingSentence(for quote: String, in transcript: String) -> String? {
    let quoteWords = Set(matchKey(quote).split(separator: " "))
    guard quoteWords.count >= 3 else { return nil }

    var best: (sentence: String, score: Double)?
    for sentence in sentences(in: transcript) {
        guard sentence.count >= 20, sentence.count <= 220 else { continue }
        let sentenceWords = Set(matchKey(sentence).split(separator: " "))
        guard !sentenceWords.isEmpty else { continue }
        let score = Double(quoteWords.intersection(sentenceWords).count) / Double(quoteWords.count)
        if score > (best?.score ?? 0) {
            best = (sentence, score)
        }
    }
    guard let best, best.score >= 0.7 else { return nil }
    return best.sentence
}
```

- [x] **Step 2.4: Run tests, verify pass**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: all `MomentNamingServiceLogicTests` PASS (existing ones stay green).

- [x] **Step 2.5: Commit**

```bash
git add Pageless/Services/MomentNamingService.swift PagelessTests/ServiceTests/MomentNamingServiceLogicTests.swift
git commit -m "feat(ai): verify moment quotes verbatim against transcript"
```

---

### Task 3: Shared generation retry helper

**Files:**
- Create: `Pageless/Services/FoundationModelGeneration.swift`

- [x] **Step 3.1: Create the helper**

`Pageless/Services/FoundationModelGeneration.swift`:

```swift
//
//  FoundationModelGeneration.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Shared typed-error mapping and single-retry policy for on-device generation.
@available(iOS 26, *)
enum FoundationModelGeneration {
    enum Failure: Error {
        /// Guardrail violation or model refusal — content was declined.
        case unsafeContent
        /// Any other generation failure, after one retry where applicable.
        case failed
    }

    /// Runs `attempt`, mapping `LanguageModelSession.GenerationError` to `Failure`
    /// and retrying once on transient errors. On `exceededContextWindowSize` the
    /// retry receives the second half of the transcript (most recent audio matters
    /// most). `attempt` must create a fresh session per call — a failed session's
    /// context is polluted.
    static func run<T>(
        transcript: String,
        attempt: (String) async throws -> T
    ) async throws -> T {
        do {
            return try await attempt(transcript)
        } catch let error as LanguageModelSession.GenerationError {
            let retryTranscript: String
            switch error {
            case .guardrailViolation, .refusal:
                throw Failure.unsafeContent
            case .exceededContextWindowSize:
                retryTranscript = String(transcript.suffix(transcript.count / 2))
            case .rateLimited, .concurrentRequests:
                try? await Task.sleep(for: .milliseconds(700))
                retryTranscript = transcript
            default:
                throw Failure.failed
            }
            do {
                return try await attempt(retryTranscript)
            } catch let retryError as LanguageModelSession.GenerationError {
                switch retryError {
                case .guardrailViolation, .refusal:
                    throw Failure.unsafeContent
                default:
                    throw Failure.failed
                }
            } catch {
                throw Failure.failed
            }
        } catch {
            throw Failure.failed
        }
    }
}
```

- [x] **Step 3.2: Build**

Run: `mcp__XcodeBuildMCP__build_device`.
Expected: BUILD SUCCEEDED.

- [x] **Step 3.3: Commit**

```bash
git add Pageless/Services/FoundationModelGeneration.swift
git commit -m "feat(ai): shared typed-error mapping and retry for generation"
```

---

### Task 4: MomentNamingService generation hardening

**Files:**
- Modify: `Pageless/Services/MomentNamingService.swift`
- Test: `PagelessTests/ServiceTests/MomentNamingServiceLogicTests.swift`

- [x] **Step 4.1: Write failing guide-sync tests**

Append to `MomentNamingServiceLogicTests`:

```swift
// MARK: - Guide value sync (guards MomentEnums drift against the @Guide literals)

@Test func categoryGuideValuesMatchEnum() {
    guard #available(iOS 26, *) else { return }
    #expect(MomentNamingService.categoryGuideValues == MomentCategory.allCases.map(\.rawValue))
}

@Test func moodGuideValuesMatchEnum() {
    guard #available(iOS 26, *) else { return }
    #expect(MomentNamingService.moodGuideValues == MomentMood.allCases.map(\.rawValue))
}
```

- [x] **Step 4.2: Run tests, verify compile failure** (`categoryGuideValues` missing).

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.

- [x] **Step 4.3: Rework `MomentNamingService` generation**

Replace the `@Generable` struct, instructions, and `analyzeMoment` in `Pageless/Services/MomentNamingService.swift` (keep `generateMomentName`, `sanitizedQuoteLine`, `verifiedQuote`, `trimToCompleteSentences`, `lastCompleteSentence`, `firstSentence`, `matchKey`, `sentences`, `bestMatchingSentence`):

```swift
@available(iOS 26, *)
struct MomentNamingService: MomentAnalyzing {
    /// Permissive content-transformation guardrails: this feature transforms the
    /// user's own audiobook audio, and default guardrails false-positive on fiction
    /// (violence/romance). Availability mirrors `SystemLanguageModel.default`.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// Greedy decoding — extraction tasks want determinism, not creativity.
    /// Token cap bounds worst-case latency; the schema fits comfortably under it.
    static let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 500)

    /// Single source for the @Guide literals below; unit tests assert these match
    /// `MomentCategory`/`MomentMood`. (Literals are repeated inside @Guide because
    /// macro arguments are captured expressions — keep all three places in sync.)
    static let categoryGuideValues = [
        "dialogue", "action", "plotTwist", "characterIntro", "worldBuilding",
        "quote", "reflection", "humor", "tension", "romance",
    ]
    static let moodGuideValues = [
        "tense", "funny", "sad", "romantic", "inspirational", "mysterious", "peaceful", "dramatic",
    ]

    // Field order matters: the model generates fields top-to-bottom and can run out
    // of output tokens before reaching the last one. Keep cheap, structured fields
    // first and put the longer prose (`momentNote`) at the end so a truncated tail
    // is recoverable by post-processing.
    @Generable(description: "Analysis of an audiobook moment bookmark")
    struct MomentNameSuggestion {
        @Guide(description: "Concise 3–5 word title in Title Case, capturing the key event or idea")
        var momentName: String

        @Guide(
            description: "1–3 categories that fit the excerpt",
            .count(1...3),
            .element(.anyOf([
                "dialogue", "action", "plotTwist", "characterIntro", "worldBuilding",
                "quote", "reflection", "humor", "tension", "romance",
            ]))
        )
        var categories: [String]

        @Guide(
            description: "Overall mood of the excerpt",
            .anyOf(["tense", "funny", "sad", "romantic", "inspirational", "mysterious", "peaceful", "dramatic"])
        )
        var mood: String

        @Guide(description: "Character names speaking or mentioned. Empty array if none.", .maximumCount(6))
        var characters: [String]

        @Guide(description: "Single most memorable line copied word-for-word from the transcript, 5 to 20 words. Must be a complete sentence ending with '.', '!' or '?'. If no complete quotable sentence exists, use an empty string — never invent or paraphrase.")
        var quoteLine: String

        @Guide(description: "Exactly 2 short sentences (max 40 words total) summarizing what is happening and why it matters. Must end with a period.")
        var momentNote: String
    }

    private static let instructionPrompt: String = {
        let parts = [
            "You analyze short excerpts from audiobooks the listener is playing. ",
            "The transcript comes from automatic speech recognition: it may contain small recognition errors. ",
            "Be concise — output is constrained by a small token budget, so every field must be complete and self-contained. Produce: ",
            "1) momentName: a 3–5 word Title Case phrase capturing the key event or idea. ",
            "2) categories: 1–3 categories that fit the excerpt. ",
            "3) mood: the overall mood. ",
            "4) characters: names of people speaking or mentioned (empty array if none). ",
            "5) quoteLine: ONE complete sentence copied word-for-word from the transcript, 5–20 words, ending in '.', '!' or '?'. If no complete quotable sentence exists, return an empty string — never invent or paraphrase. ",
            "6) momentNote: exactly 2 short sentences (max 40 words total) summarizing what is happening and why it matters. Both sentences must end with a period. Never leave a sentence unfinished.",
        ]
        return parts.joined()
    }()

    private let instructions = Instructions(Self.instructionPrompt)

    /// Loads model resources before the first analyze call. The prewarmed session is
    /// consumed by exactly one analysis (sessions are multi-turn; reuse would pollute
    /// the next analysis's context).
    func prewarm() {
        let instructions = self.instructions
        Task { @MainActor in
            guard Self.model.isAvailable, PrewarmedMomentSession.session == nil else { return }
            let session = LanguageModelSession(model: Self.model, instructions: instructions)
            session.prewarm()
            PrewarmedMomentSession.session = session
        }
    }

    func generateMomentName(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> (name: String, note: String) {
        let analysis = try await analyzeMoment(transcript: transcript, audiobookTitle: audiobookTitle)
        return (name: analysis.name, note: analysis.note)
    }

    func analyzeMoment(
        transcript: String,
        audiobookTitle: String? = nil
    ) async throws -> MomentAnalysis {
        guard Self.model.isAvailable else {
            throw MomentNamingError.modelUnavailable
        }

        let instructions = self.instructions
        let content: MomentNameSuggestion
        do {
            var isFirstAttempt = true
            content = try await FoundationModelGeneration.run(transcript: transcript) { attemptTranscript in
                let session: LanguageModelSession
                if isFirstAttempt, let prewarmed = await PrewarmedMomentSession.take() {
                    session = prewarmed
                } else {
                    session = LanguageModelSession(model: Self.model, instructions: instructions)
                }
                isFirstAttempt = false

                var promptText = "Analyze this audiobook excerpt:\n\n\"\(attemptTranscript)\""
                if let title = audiobookTitle, !title.isEmpty {
                    promptText += "\n\nFrom: \(title)"
                }
                let response = try await session.respond(
                    to: Prompt(promptText),
                    generating: MomentNameSuggestion.self,
                    options: Self.options
                )
                return response.content
            }
        } catch FoundationModelGeneration.Failure.unsafeContent {
            throw MomentNamingError.unsafeContent
        } catch let error as MomentNamingError {
            throw error
        } catch {
            throw MomentNamingError.generationFailed
        }

        let trimSet = CharacterSet.whitespacesAndNewlines
        let name = content.momentName.trimmingCharacters(in: trimSet)
        let note = trimToCompleteSentences(content.momentNote)
        let categories = content.categories.compactMap { MomentCategory(rawValue: $0) }
        let quote = verifiedQuote(content.quoteLine, transcript: transcript)
        let characters = content.characters.map { $0.trimmingCharacters(in: trimSet) }.filter { !$0.isEmpty }
        let mood = MomentMood(rawValue: content.mood.trimmingCharacters(in: trimSet))

        return MomentAnalysis(
            name: name.isEmpty ? "Saved Moment" : name,
            note: note,
            categories: categories,
            quoteLine: quote.isEmpty ? nil : quote,
            characters: characters,
            mood: mood
        )
    }

    // … existing helpers unchanged (sanitizedQuoteLine, verifiedQuote, matchKey,
    // sentences, bestMatchingSentence, trimToCompleteSentences,
    // lastCompleteSentence, firstSentence) …
}

/// Holds at most one prewarmed session, consumed by the next analysis.
@available(iOS 26, *)
@MainActor
enum PrewarmedMomentSession {
    static var session: LanguageModelSession?

    static func take() -> LanguageModelSession? {
        defer { session = nil }
        return session
    }
}
```

- [x] **Step 4.4: Run tests**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: all PASS (guide-sync tests now compile and pass; existing quote/note tests unaffected).

- [x] **Step 4.5: Commit**

```bash
git add Pageless/Services/MomentNamingService.swift PagelessTests/ServiceTests/MomentNamingServiceLogicTests.swift
git commit -m "feat(ai): permissive guardrails, constrained guides, greedy sampling, retry, prewarm for moment naming"
```

---

### Task 5: RecapService generation hardening

**Files:**
- Modify: `Pageless/Services/RecapService.swift`

- [x] **Step 5.1: Rework `RecapService`**

Replace the body of `Pageless/Services/RecapService.swift` (keep `sanitizeHeadline`):

```swift
@available(iOS 26, *)
struct RecapService: RecapProviding {
    /// See MomentNamingService.model — same rationale.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    static let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 300)

    @Generable(description: "A brief recap of recent audiobook events")
    struct RecapSuggestion {
        @Guide(description: "2-sentence summary of what happened recently in the audiobook. Both sentences must end with a period.")
        var recap: String
    }

    // Headline first: fields generate in declaration order and the token budget can
    // clip the tail — the short headline must never be the field that gets clipped.
    @Generable(description: "Recap plus a one-line headline for the progress row")
    struct RecapWithHeadlineSuggestion {
        @Guide(description: "Exactly 3 to 4 words summarizing where the listener left off, for a single UI line. No punctuation at the end.")
        var progressHeadline: String
        @Guide(description: "2-sentence summary of what happened recently in the audiobook. Both sentences must end with a period.")
        var recap: String
    }

    private let instructions = Instructions(
        "You are an assistant that helps audiobook listeners remember where they left off. " +
        "The transcript comes from automatic speech recognition and may contain small errors. " +
        "Given a transcript of the most recent audio, write a 2-sentence summary of what just happened. " +
        "Focus on key events, character actions, and plot developments. Be concise and spoiler-aware."
    )

    private let instructionsWithHeadline = Instructions(
        "You are an assistant that helps audiobook listeners remember where they left off. " +
        "The transcript comes from automatic speech recognition and may contain small errors. " +
        "Given a transcript of the most recent audio, provide progressHeadline: exactly 3 to 4 words that capture the gist for a single-line UI label (no ending punctuation). " +
        "Then write a 2-sentence summary of what just happened. " +
        "Focus on key events and be spoiler-aware."
    )

    func generateRecap(
        transcript: String,
        audiobookTitle: String? = nil,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        guard Self.model.isAvailable else {
            throw RecapError.modelUnavailable
        }

        do {
            if includeProgressHeadline {
                let instructions = instructionsWithHeadline
                let content = try await FoundationModelGeneration.run(transcript: transcript) { attemptTranscript in
                    let session = LanguageModelSession(model: Self.model, instructions: instructions)
                    let response = try await session.respond(
                        to: Prompt(Self.promptText(transcript: attemptTranscript, title: audiobookTitle)),
                        generating: RecapWithHeadlineSuggestion.self,
                        options: Self.options
                    )
                    return response.content
                }
                return RecapGenerationResult(
                    recap: content.recap.trimmingCharacters(in: .whitespacesAndNewlines),
                    progressHeadline: Self.sanitizeHeadline(content.progressHeadline)
                )
            } else {
                let instructions = self.instructions
                let content = try await FoundationModelGeneration.run(transcript: transcript) { attemptTranscript in
                    let session = LanguageModelSession(model: Self.model, instructions: instructions)
                    let response = try await session.respond(
                        to: Prompt(Self.promptText(transcript: attemptTranscript, title: audiobookTitle)),
                        generating: RecapSuggestion.self,
                        options: Self.options
                    )
                    return response.content
                }
                return RecapGenerationResult(
                    recap: content.recap.trimmingCharacters(in: .whitespacesAndNewlines),
                    progressHeadline: nil
                )
            }
        } catch FoundationModelGeneration.Failure.unsafeContent {
            throw RecapError.unsafeContent
        } catch let error as RecapError {
            throw error
        } catch {
            throw RecapError.generationFailed
        }
    }

    static func promptText(transcript: String, title: String?) -> String {
        var promptText = "Summarize what just happened in this audiobook excerpt:\n\n\"\(transcript)\""
        if let title, !title.isEmpty {
            promptText += "\n\nFrom: \(title)"
        }
        return promptText
    }

    /// Keeps at most four words for a single-line UI label.
    static func sanitizeHeadline(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return trimmed }
        return words.prefix(4).joined(separator: " ")
    }
}
```

- [x] **Step 5.2: Run tests** (RecapServiceLogicTests must stay green)

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: PASS.

- [x] **Step 5.3: Commit**

```bash
git add Pageless/Services/RecapService.swift
git commit -m "feat(ai): permissive guardrails, greedy sampling, retry, headline-first schema for recap"
```

---

### Task 6: `SegmentTranscribing` protocol + stub + mock

**Files:**
- Create: `Pageless/Services/Protocols/SegmentTranscribing.swift`
- Create: `PagelessTests/Mocks/MockSegmentTranscriber.swift`

- [x] **Step 6.1: Create the protocol file**

`Pageless/Services/Protocols/SegmentTranscribing.swift`:

```swift
//
//  SegmentTranscribing.swift
//  Pageless
//

import Foundation

enum SegmentTranscriptionError: LocalizedError {
    case unsupported
    case invalidRange
    case audioUnreadable
    case localeUnavailable
    case analysisFailed
    case emptyResult

    var errorDescription: String? {
        "Could not transcribe audio."
    }
}

/// Transcribes a time range of an audio file directly — no export step and no
/// speech-recognition permission. Implemented by the iOS 26 SpeechAnalyzer service;
/// callers fall back to `AudioExtracting` + `TranscriptionProviding` on failure.
protocol SegmentTranscribing: Sendable {
    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String
}

/// Default transcriber on iOS versions without SpeechAnalyzer. Always throws, which
/// routes callers onto the legacy export + SFSpeechRecognizer path.
struct UnavailableSegmentTranscriber: SegmentTranscribing {
    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        throw SegmentTranscriptionError.unsupported
    }
}
```

- [x] **Step 6.2: Create the mock**

`PagelessTests/Mocks/MockSegmentTranscriber.swift`:

```swift
//
//  MockSegmentTranscriber.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

final class MockSegmentTranscriber: SegmentTranscribing, @unchecked Sendable {
    var transcriptToReturn = "Mock segment transcript"
    var shouldThrow = false
    var callCount = 0
    var lastRange: (start: Double, end: Double)?

    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        callCount += 1
        lastRange = (startSeconds, endSeconds)
        if shouldThrow { throw SegmentTranscriptionError.audioUnreadable }
        return transcriptToReturn
    }
}
```

- [x] **Step 6.3: Build**

Run: `mcp__XcodeBuildMCP__build_device`.
Expected: BUILD SUCCEEDED.

- [x] **Step 6.4: Commit**

```bash
git add Pageless/Services/Protocols/SegmentTranscribing.swift PagelessTests/Mocks/MockSegmentTranscriber.swift
git commit -m "feat(ai): SegmentTranscribing protocol with iOS 18 stub and test mock"
```

---

### Task 7: `SpeechAnalyzerTranscriptionService` (TDD on locale matching)

**Files:**
- Create: `Pageless/Services/SpeechAnalyzerTranscriptionService.swift`
- Test: `PagelessTests/ServiceTests/MomentNamingServiceLogicTests.swift` → new file `PagelessTests/ServiceTests/SpeechAnalyzerTranscriptionServiceTests.swift`

- [x] **Step 7.1: Write failing locale-matching tests**

`PagelessTests/ServiceTests/SpeechAnalyzerTranscriptionServiceTests.swift`:

```swift
//
//  SpeechAnalyzerTranscriptionServiceTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct SpeechAnalyzerTranscriptionServiceTests {
    @Test func bestMatchPrefersExactLocale() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "en_GB"), Locale(identifier: "en_US"), Locale(identifier: "fr_FR")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "en_US"))
        #expect(match?.identifier(.bcp47) == "en-US")
    }

    @Test func bestMatchFallsBackToSameLanguage() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "fr_FR"), Locale(identifier: "en_GB")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "en_US"))
        #expect(match?.identifier(.bcp47) == "en-GB")
    }

    @Test func bestMatchFallsBackToEnglish() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "fr_FR"), Locale(identifier: "en_US")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "ro_RO"))
        #expect(match?.identifier(.bcp47) == "en-US")
    }

    @Test func bestMatchReturnsNilWhenNothingFits() {
        guard #available(iOS 26, *) else { return }
        let locales = [Locale(identifier: "fr_FR")]
        let match = SpeechAnalyzerTranscriptionService.bestMatch(in: locales, for: Locale(identifier: "ro_RO"))
        #expect(match == nil)
    }
}
```

- [x] **Step 7.2: Run tests, verify compile failure** (type missing).

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.

- [x] **Step 7.3: Create the service**

`Pageless/Services/SpeechAnalyzerTranscriptionService.swift`:

```swift
//
//  SpeechAnalyzerTranscriptionService.swift
//  Pageless
//

import AVFoundation
import Foundation
import Speech

/// Transcribes a time range of an audio file with the iOS 26 SpeechAnalyzer API.
/// Compared with the legacy export + SFSpeechRecognizer path: no temp file, no
/// re-encode, no speech-recognition permission, no audio-length cap, punctuated
/// output, faster than realtime.
@available(iOS 26, *)
struct SpeechAnalyzerTranscriptionService: SegmentTranscribing {
    /// ~1.5 s of audio at 44.1 kHz per buffer handed to the analyzer.
    private static let chunkFrames: AVAudioFrameCount = 65_536

    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        guard endSeconds > startSeconds else { throw SegmentTranscriptionError.invalidRange }

        let locale = try await Self.resolveLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw SegmentTranscriptionError.audioUnreadable
        }

        let fileFormat = audioFile.processingFormat
        let sampleRate = fileFormat.sampleRate
        guard sampleRate > 0, audioFile.length > 0 else { throw SegmentTranscriptionError.audioUnreadable }

        let startFrame = AVAudioFramePosition(max(0, startSeconds) * sampleRate)
        let endFrame = min(AVAudioFramePosition(endSeconds * sampleRate), audioFile.length)
        guard endFrame > startFrame, startFrame < audioFile.length else {
            throw SegmentTranscriptionError.invalidRange
        }

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: fileFormat
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        let feeder = AudioSegmentFeeder(
            file: audioFile,
            startFrame: startFrame,
            endFrame: endFrame,
            chunkFrames: Self.chunkFrames,
            outputFormat: analyzerFormat
        )
        let feedTask = Task.detached(priority: .userInitiated) {
            try feeder.feed(into: inputBuilder)
        }

        let resultsTask = Task {
            var pieces: [String] = []
            for try await result in transcriber.results {
                pieces.append(String(result.text.characters))
            }
            return pieces.joined(separator: " ")
        }

        do {
            _ = try await analyzer.analyzeSequence(inputSequence)
            try await feedTask.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            feedTask.cancel()
            resultsTask.cancel()
            throw SegmentTranscriptionError.analysisFailed
        }

        let text: String
        do {
            text = try await resultsTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw SegmentTranscriptionError.analysisFailed
        }
        guard !text.isEmpty else { throw SegmentTranscriptionError.emptyResult }
        return text
    }

    /// Installed locales first (no download), then supported (one-time asset
    /// download); exact match → same language → English; else unavailable.
    static func resolveLocale() async throws -> Locale {
        if let match = bestMatch(in: await SpeechTranscriber.installedLocales, for: Locale.current) {
            return match
        }
        if let match = bestMatch(in: await SpeechTranscriber.supportedLocales, for: Locale.current) {
            return match
        }
        throw SegmentTranscriptionError.localeUnavailable
    }

    static func bestMatch(in locales: [Locale], for current: Locale) -> Locale? {
        if let exact = locales.first(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) {
            return exact
        }
        if let sameLanguage = locales.first(where: { $0.language.languageCode == current.language.languageCode }) {
            return sameLanguage
        }
        return locales.first(where: { $0.language.languageCode == Locale.LanguageCode("en") })
    }
}

/// Reads the requested frame range chunk-by-chunk and feeds it to the analyzer,
/// converting to the analyzer's preferred format when it differs from the file's.
/// Class (not struct) so the non-Sendable AVAudioFile/AVAudioConverter are confined
/// to the single feeding task.
@available(iOS 26, *)
private final class AudioSegmentFeeder: @unchecked Sendable {
    private let file: AVAudioFile
    private let startFrame: AVAudioFramePosition
    private let endFrame: AVAudioFramePosition
    private let chunkFrames: AVAudioFrameCount
    private let outputFormat: AVAudioFormat?
    private let converter: AVAudioConverter?

    init(
        file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        chunkFrames: AVAudioFrameCount,
        outputFormat: AVAudioFormat?
    ) {
        self.file = file
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.chunkFrames = chunkFrames
        self.outputFormat = outputFormat
        if let outputFormat, outputFormat != file.processingFormat {
            self.converter = AVAudioConverter(from: file.processingFormat, to: outputFormat)
        } else {
            self.converter = nil
        }
    }

    func feed(into builder: AsyncStream<AnalyzerInput>.Continuation) throws {
        defer { builder.finish() }
        file.framePosition = startFrame
        var remaining = AVAudioFrameCount(endFrame - startFrame)

        while remaining > 0 {
            try Task.checkCancellation()
            let frames = min(remaining, chunkFrames)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                throw SegmentTranscriptionError.audioUnreadable
            }
            try file.read(into: buffer, frameCount: frames)
            guard buffer.frameLength > 0 else { break }
            remaining -= buffer.frameLength
            builder.yield(AnalyzerInput(buffer: try converted(buffer)))
        }
    }

    private func converted(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter, let outputFormat else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SegmentTranscriptionError.audioUnreadable
        }
        var fed = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError {
            throw conversionError
        }
        return outBuffer
    }
}
```

- [x] **Step 7.4: Run tests**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: locale tests PASS; full suite green.

If `analyzeSequence`/`makeStream`/actor-isolation produces compile errors, consult the swiftinterface at
`$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-ios.swiftinterface`
— signatures listed in the header of this plan are authoritative.

- [x] **Step 7.5: Commit**

```bash
git add Pageless/Services/SpeechAnalyzerTranscriptionService.swift PagelessTests/ServiceTests/SpeechAnalyzerTranscriptionServiceTests.swift
git commit -m "feat(ai): SpeechAnalyzer segment transcription (no export, no permission)"
```

---

### Task 8: Harden legacy `TranscriptionService`

**Files:**
- Modify: `Pageless/Services/TranscriptionService.swift:23-29`

- [x] **Step 8.1: Harden `transcribe(audioURL:)`**

Replace the top of `transcribe(audioURL:)`:

```swift
    func transcribe(audioURL: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        // Punctuated output keeps sentence-based post-processing working.
        request.addsPunctuation = true
        // Server-based recognition caps audio at ~1 minute; our segments are longer.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // … rest unchanged …
```

- [x] **Step 8.2: Build**

Run: `mcp__XcodeBuildMCP__build_device`.
Expected: BUILD SUCCEEDED.

- [x] **Step 8.3: Commit**

```bash
git add Pageless/Services/TranscriptionService.swift
git commit -m "fix(ai): punctuation, on-device recognition, locale fallback in legacy transcription"
```

---

### Task 9: `PlayerViewModel` pipeline rework (TDD)

**Files:**
- Modify: `Pageless/ViewModels/PlayerViewModel.swift`
- Modify: `PagelessTests/Mocks/MockMomentAnalyzer.swift`
- Modify: `PagelessTests/Mocks/MockTranscriptionService.swift`
- Test: `PagelessTests/ViewModelTests/PlayerViewModelTests.swift`

- [x] **Step 9.1: Extend mocks**

`MockMomentAnalyzer` — add `errorToThrow` (keep `shouldThrow`):

```swift
final class MockMomentAnalyzer: MomentAnalyzing, @unchecked Sendable {
    var analysisToReturn: MomentAnalysis?
    var shouldThrow = false
    var errorToThrow: Error?
    var prewarmCallCount = 0

    func prewarm() { prewarmCallCount += 1 }

    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentAnalysis {
        if let errorToThrow { throw errorToThrow }
        if shouldThrow { throw MomentNamingError.modelUnavailable }
        return analysisToReturn ?? MomentAnalysis(
            name: "Test Moment",
            note: "Test note",
            categories: [.dialogue],
            quoteLine: "A test quote",
            characters: ["Alice"],
            mood: .mysterious
        )
    }
}
```

`MockTranscriptionService` — add counters:

```swift
final class MockTranscriptionService: TranscriptionProviding, @unchecked Sendable {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized
    var transcriptToReturn: String = "Mock transcript text"
    var shouldThrow = false
    var authorizationRequestCount = 0
    var transcribeCallCount = 0

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationRequestCount += 1
        return authorizationStatus
    }

    func transcribe(audioURL: URL) async throws -> String {
        transcribeCallCount += 1
        if shouldThrow { throw TranscriptionError.recognizerUnavailable }
        return transcriptToReturn
    }
}
```

- [x] **Step 9.2: Write failing tests**

Replace `makeViewModel` in `PlayerViewModelTests` and append tests:

```swift
private func makeViewModel(
    transcription: MockTranscriptionService = MockTranscriptionService(),
    analyzer: MockMomentAnalyzer = MockMomentAnalyzer(),
    extractor: MockAudioExtractor = MockAudioExtractor(),
    segmentTranscriber: MockSegmentTranscriber = MockSegmentTranscriber()
) -> PlayerViewModel {
    PlayerViewModel(
        transcription: transcription,
        momentAnalyzer: analyzer,
        audioExtractor: extractor,
        segmentTranscriber: segmentTranscriber
    )
}
```

```swift
// MARK: - obtainTranscript

@Test func obtainTranscriptUsesPrimaryPathWithoutAuthorization() async {
    let transcription = MockTranscriptionService()
    let segment = MockSegmentTranscriber()
    segment.transcriptToReturn = "primary transcript"
    let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

    let result = await vm.obtainTranscript(
        fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
    )

    #expect(result == "primary transcript")
    #expect(transcription.authorizationRequestCount == 0)
    #expect(transcription.transcribeCallCount == 0)
}

@Test func obtainTranscriptUsesBacktrackHeavyWindow() async {
    let segment = MockSegmentTranscriber()
    let vm = makeViewModel(segmentTranscriber: segment)

    _ = await vm.obtainTranscript(
        fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
    )

    #expect(segment.lastRange?.start == 25)   // 100 − 75
    #expect(segment.lastRange?.end == 115)    // 100 + 15
}

@Test func obtainTranscriptClampsWindowToTrackBounds() async {
    let segment = MockSegmentTranscriber()
    let vm = makeViewModel(segmentTranscriber: segment)

    _ = await vm.obtainTranscript(
        fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 10, duration: 18
    )

    #expect(segment.lastRange?.start == 0)
    #expect(segment.lastRange?.end == 18)
}

@Test func obtainTranscriptFallsBackToLegacyWhenPrimaryThrows() async {
    let transcription = MockTranscriptionService()
    transcription.transcriptToReturn = "legacy transcript"
    let segment = MockSegmentTranscriber()
    segment.shouldThrow = true
    let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

    let result = await vm.obtainTranscript(
        fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
    )

    #expect(result == "legacy transcript")
    #expect(transcription.authorizationRequestCount == 1)
}

@Test func obtainTranscriptReturnsNilWhenPrimaryFailsAndAuthDenied() async {
    let transcription = MockTranscriptionService()
    transcription.authorizationStatus = .denied
    let segment = MockSegmentTranscriber()
    segment.shouldThrow = true
    let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

    let result = await vm.obtainTranscript(
        fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
    )

    #expect(result == nil)
    #expect(transcription.transcribeCallCount == 0)
}

// MARK: - applyAnalysis

@Test func applyAnalysisPopulatesPendingFields() async {
    let analyzer = MockMomentAnalyzer()
    let vm = makeViewModel(analyzer: analyzer)

    await vm.applyAnalysis(transcript: "some transcript", audiobookTitle: "Book", savedTime: 42)

    #expect(vm.momentNameInput == "Test Moment")
    #expect(vm.momentNoteInput == "Test note")
    #expect(vm.pendingMomentAiGenerated == true)
    #expect(vm.pendingCategories == [.dialogue])
    #expect(vm.pendingQuoteLine == "A test quote")
    #expect(vm.pendingCharacters == ["Alice"])
    #expect(vm.pendingMood == .mysterious)
    #expect(vm.pendingMomentTime == 42)
    #expect(vm.pendingSmartSaveUnsafeWarning == false)
}

@Test func applyAnalysisSetsUnsafeWarningOnUnsafeContent() async {
    let analyzer = MockMomentAnalyzer()
    analyzer.errorToThrow = MomentNamingError.unsafeContent
    let vm = makeViewModel(analyzer: analyzer)

    await vm.applyAnalysis(transcript: "some transcript", audiobookTitle: "Book", savedTime: 42)

    #expect(vm.pendingSmartSaveUnsafeWarning == true)
    #expect(vm.pendingMomentTranscript == "some transcript")
    #expect(vm.pendingMomentTime == 42)
    #expect(vm.pendingMomentAiGenerated == false)
}

@Test func applyAnalysisClearsUnsafeWarningOnOtherErrors() async {
    let analyzer = MockMomentAnalyzer()
    analyzer.errorToThrow = MomentNamingError.generationFailed
    let vm = makeViewModel(analyzer: analyzer)

    await vm.applyAnalysis(transcript: "some transcript", audiobookTitle: "Book", savedTime: 42)

    #expect(vm.pendingSmartSaveUnsafeWarning == false)
    #expect(vm.pendingMomentTranscript == "some transcript")
    #expect(vm.pendingMomentTime == 42)
}

@Test func prewarmSmartSaveForwardsToAnalyzer() {
    let analyzer = MockMomentAnalyzer()
    let vm = makeViewModel(analyzer: analyzer)

    vm.prewarmSmartSave()

    #expect(analyzer.prewarmCallCount == 1)
}
```

- [x] **Step 9.3: Run tests, verify compile failure** (new init param / methods missing).

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.

- [x] **Step 9.4: Rework `PlayerViewModel`**

In `Pageless/ViewModels/PlayerViewModel.swift`:

Add the dependency + constants:

```swift
    // Context window around "now": the moment is what the user just heard, so weight
    // the window behind the playhead; future audio is noise/spoilers and costs time.
    static let momentContextBackSeconds: Double = 75
    static let momentContextForwardSeconds: Double = 15

    private let segmentTranscriber: any SegmentTranscribing

    init(
        transcription: (any TranscriptionProviding)? = nil,
        momentAnalyzer: (any MomentAnalyzing)? = nil,
        audioExtractor: (any AudioExtracting)? = nil,
        segmentTranscriber: (any SegmentTranscribing)? = nil
    ) {
        self.transcription = transcription ?? TranscriptionService()
        if let momentAnalyzer {
            self.momentAnalyzer = momentAnalyzer
        } else if #available(iOS 26, *) {
            self.momentAnalyzer = MomentNamingService()
        } else {
            self.momentAnalyzer = UnavailableMomentAnalyzer()
        }
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        if let segmentTranscriber {
            self.segmentTranscriber = segmentTranscriber
        } else if #available(iOS 26, *) {
            self.segmentTranscriber = SpeechAnalyzerTranscriptionService()
        } else {
            self.segmentTranscriber = UnavailableSegmentTranscriber()
        }
    }

    /// Loads model resources ahead of a likely smart save (called when the player opens).
    func prewarmSmartSave() {
        momentAnalyzer.prewarm()
    }
```

Replace `performSmartSave` with the split pipeline:

```swift
    private func performSmartSave(
        player: AudioPlayerManager,
        savedTime: Double,
        momentBacktrackSeconds: Double,
        onSuccessfulSmartAI: (() -> Void)?
    ) async {
        guard let audiobook = player.currentAudiobook,
              let track = player.currentTrack else { return }

        isProcessingSmartSave = true
        defer { isProcessingSmartSave = false }

        guard let fileURL = try? LibraryImportService.fileURL(for: track, in: audiobook),
              let transcript = await obtainTranscript(
                  fileURL: fileURL,
                  currentTime: player.currentTime,
                  duration: player.duration
              ),
              !transcript.isEmpty
        else {
            resetMomentState()
            pendingMomentTime = savedTime
            return
        }

        await applyAnalysis(
            transcript: transcript,
            audiobookTitle: audiobook.title,
            savedTime: savedTime,
            onSuccessfulSmartAI: onSuccessfulSmartAI
        )
    }

    /// SpeechAnalyzer first (no permission, no export); legacy export +
    /// SFSpeechRecognizer fallback, which is the only path that needs authorization.
    /// Internal for tests.
    func obtainTranscript(fileURL: URL, currentTime: Double, duration: Double) async -> String? {
        momentAnalyzer.prewarm() // overlap model load with transcription

        let start = max(0, currentTime - Self.momentContextBackSeconds)
        let end = min(duration, currentTime + Self.momentContextForwardSeconds)
        if end > start,
           let transcript = try? await segmentTranscriber.transcribeSegment(
               fileURL: fileURL, startSeconds: start, endSeconds: end
           ),
           !transcript.isEmpty {
            return transcript
        }

        let authStatus = await transcription.requestAuthorization()
        guard authStatus == .authorized else { return nil }
        do {
            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL, currentTime: currentTime, duration: duration
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }
            return try await transcription.transcribe(audioURL: audioURL)
        } catch {
            return nil
        }
    }

    /// Runs the analyzer and fills the pending-moment fields. Internal for tests.
    func applyAnalysis(
        transcript: String,
        audiobookTitle: String,
        savedTime: Double,
        onSuccessfulSmartAI: (() -> Void)? = nil
    ) async {
        do {
            let analysis = try await momentAnalyzer.analyzeMoment(
                transcript: transcript,
                audiobookTitle: audiobookTitle
            )
            momentNameInput = analysis.name
            momentNoteInput = analysis.note
            pendingMomentTranscript = transcript
            pendingMomentAiGenerated = true
            pendingCategories = analysis.categories
            pendingQuoteLine = analysis.quoteLine
            pendingCharacters = analysis.characters
            pendingMood = analysis.mood
            pendingSmartSaveUnsafeWarning = false
            pendingMomentTime = savedTime
            onSuccessfulSmartAI?()
        } catch {
            resetMomentState()
            pendingMomentTranscript = transcript
            pendingSmartSaveUnsafeWarning = (error as? MomentNamingError) == .unsafeContent
            pendingMomentTime = savedTime
        }
    }
```

Note: the old up-front `transcription.requestAuthorization()` guard at the top of
`performSmartSave` is **deleted** — authorization belongs to the legacy fallback only.

- [x] **Step 9.5: Run tests**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: all PlayerViewModel tests PASS (including pre-existing ones).

- [x] **Step 9.6: Commit**

```bash
git add Pageless/ViewModels/PlayerViewModel.swift PagelessTests/Mocks/MockMomentAnalyzer.swift PagelessTests/Mocks/MockTranscriptionService.swift PagelessTests/ViewModelTests/PlayerViewModelTests.swift
git commit -m "feat(ai): permission-free smart save pipeline with legacy fallback and typed unsafe handling"
```

---

### Task 10: `AudiobookDetailViewModel` pipeline rework (TDD)

**Files:**
- Modify: `Pageless/ViewModels/AudiobookDetailViewModel.swift`
- Modify: `PagelessTests/Mocks/MockRecapService.swift`
- Test: `PagelessTests/ViewModelTests/AudiobookDetailViewModelTests.swift`

- [x] **Step 10.1: Extend `MockRecapService`**

```swift
final class MockRecapService: RecapProviding, @unchecked Sendable {
    var recapToReturn = "Mock recap of recent events."
    var progressHeadlineToReturn: String?
    var shouldThrow = false
    var errorToThrow: Error?

    func generateRecap(
        transcript: String,
        audiobookTitle: String?,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        if let errorToThrow { throw errorToThrow }
        if shouldThrow { throw RecapError.modelUnavailable }
        let headline = includeProgressHeadline ? (progressHeadlineToReturn ?? "Left mid chase scene") : nil
        return RecapGenerationResult(recap: recapToReturn, progressHeadline: headline)
    }
}
```

- [x] **Step 10.2: Write failing tests**

In `AudiobookDetailViewModelTests`, update `makeViewModel` and the two direct `AudiobookDetailViewModel(...)` constructions (in `reconcileStoredRecapClearsMismatchedPersistedRecap`, `loadRecapStoresRecapOnAudiobook`, `loadRecapWithoutHeadlineStoresNilHeadlineOnAudiobook`) to pass `segmentTranscriber: MockSegmentTranscriber()`. Then append:

```swift
@Test func loadRecapPrimaryPathSkipsAuthorization() async throws {
    let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)

    let book = Audiobook(title: "T3", author: "", folderName: "primary-path-test", totalDuration: 600)
    let track = AudioTrack(
        title: "Ch1",
        originalFileName: "c.m4a",
        storedFileName: "c.m4a",
        orderIndex: 0,
        duration: 600,
        audiobook: book
    )
    book.tracks.append(track)
    context.insert(book)

    let transcription = MockTranscriptionService()
    let segment = MockSegmentTranscriber()
    let vm = AudiobookDetailViewModel(
        audiobook: book,
        transcription: transcription,
        audioExtractor: MockAudioExtractor(),
        recapProvider: MockRecapService(),
        segmentTranscriber: segment
    )
    await vm.loadRecap(trackIndex: 0, progressTime: 300, includeProgressHeadline: false, modelContext: context)

    #expect(vm.recapText == "Mock recap of recent events.")
    #expect(segment.callCount == 1)
    #expect(segment.lastRange?.start == 100)  // 300 − 200
    #expect(segment.lastRange?.end == 300)
    #expect(transcription.authorizationRequestCount == 0)
}

@Test func loadRecapFallsBackToLegacyWhenPrimaryThrows() async throws {
    let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)

    let book = Audiobook(title: "T4", author: "", folderName: "fallback-path-test", totalDuration: 600)
    let track = AudioTrack(
        title: "Ch1",
        originalFileName: "d.m4a",
        storedFileName: "d.m4a",
        orderIndex: 0,
        duration: 600,
        audiobook: book
    )
    book.tracks.append(track)
    context.insert(book)

    let transcription = MockTranscriptionService()
    let segment = MockSegmentTranscriber()
    segment.shouldThrow = true
    let vm = AudiobookDetailViewModel(
        audiobook: book,
        transcription: transcription,
        audioExtractor: MockAudioExtractor(),
        recapProvider: MockRecapService(),
        segmentTranscriber: segment
    )
    await vm.loadRecap(trackIndex: 0, progressTime: 300, includeProgressHeadline: false, modelContext: context)

    #expect(vm.recapText == "Mock recap of recent events.")
    #expect(transcription.authorizationRequestCount == 1)
    #expect(transcription.transcribeCallCount == 1)
}

@Test func produceRecapSurfacesUnsafeContentCopy() async {
    let recap = MockRecapService()
    recap.errorToThrow = RecapError.unsafeContent
    let vm = AudiobookDetailViewModel(
        audiobook: makeAudiobook(),
        transcription: MockTranscriptionService(),
        audioExtractor: MockAudioExtractor(),
        recapProvider: recap,
        segmentTranscriber: MockSegmentTranscriber()
    )

    await vm.produceRecap(
        transcript: "t", includeProgressHeadline: false,
        anchorTrackIndex: 0, anchorTime: 1, modelContext: nil, onSuccessfulRecap: nil
    )

    #expect(vm.recapError == "Apple Intelligence declined to summarize this passage.")
    #expect(vm.recapText == nil)
}
```

- [x] **Step 10.3: Run tests, verify compile failure.**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.

- [x] **Step 10.4: Rework `AudiobookDetailViewModel`**

Add the dependency (same init pattern as PlayerViewModel):

```swift
    private let segmentTranscriber: any SegmentTranscribing

    init(
        audiobook: Audiobook,
        transcription: (any TranscriptionProviding)? = nil,
        audioExtractor: (any AudioExtracting)? = nil,
        recapProvider: (any RecapProviding)? = nil,
        segmentTranscriber: (any SegmentTranscribing)? = nil
    ) {
        self.audiobook = audiobook
        self.transcription = transcription ?? TranscriptionService()
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        if let recapProvider {
            self.recapProvider = recapProvider
        } else if #available(iOS 26, *) {
            self.recapProvider = RecapService()
        } else {
            self.recapProvider = UnavailableRecapProvider()
        }
        if let segmentTranscriber {
            self.segmentTranscriber = segmentTranscriber
        } else if #available(iOS 26, *) {
            self.segmentTranscriber = SpeechAnalyzerTranscriptionService()
        } else {
            self.segmentTranscriber = UnavailableSegmentTranscriber()
        }
        syncRecapFromAudiobook()
    }
```

Replace `loadRecap` with the split pipeline:

```swift
    func loadRecap(
        trackIndex: Int,
        progressTime: Double,
        includeProgressHeadline: Bool,
        modelContext: ModelContext? = nil,
        onSuccessfulRecap: (() -> Void)? = nil
    ) async {
        isLoadingRecap = true
        defer { isLoadingRecap = false }

        let tracks = audiobook.sortedTracks
        guard tracks.indices.contains(trackIndex) else { return }
        guard let fileURL = try? LibraryImportService.fileURL(for: tracks[trackIndex], in: audiobook) else {
            recapError = "Audio for this book isn't on this iPhone."
            return
        }

        let startSeconds = max(0, progressTime - 200)
        guard progressTime > startSeconds else { return }

        guard let transcript = await obtainTranscript(
            fileURL: fileURL, startSeconds: startSeconds, endSeconds: progressTime
        ), !transcript.isEmpty else {
            if recapError == nil { recapError = "Could not transcribe audio." }
            return
        }

        await produceRecap(
            transcript: transcript,
            includeProgressHeadline: includeProgressHeadline,
            anchorTrackIndex: trackIndex,
            anchorTime: progressTime,
            modelContext: modelContext,
            onSuccessfulRecap: onSuccessfulRecap
        )
    }

    /// SpeechAnalyzer first (no permission, no export); legacy export +
    /// SFSpeechRecognizer fallback. Internal for tests.
    func obtainTranscript(fileURL: URL, startSeconds: Double, endSeconds: Double) async -> String? {
        if let transcript = try? await segmentTranscriber.transcribeSegment(
            fileURL: fileURL, startSeconds: startSeconds, endSeconds: endSeconds
        ), !transcript.isEmpty {
            return transcript
        }

        let authStatus = await transcription.requestAuthorization()
        guard authStatus == .authorized else {
            recapError = "Speech recognition not authorized."
            return nil
        }
        do {
            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL, startSeconds: startSeconds, endSeconds: endSeconds
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }
            return try await transcription.transcribe(audioURL: audioURL)
        } catch {
            return nil
        }
    }

    /// Runs the recap provider and persists the result. Internal for tests.
    func produceRecap(
        transcript: String,
        includeProgressHeadline: Bool,
        anchorTrackIndex: Int,
        anchorTime: Double,
        modelContext: ModelContext?,
        onSuccessfulRecap: (() -> Void)?
    ) async {
        do {
            let result = try await recapProvider.generateRecap(
                transcript: transcript,
                audiobookTitle: audiobook.title,
                includeProgressHeadline: includeProgressHeadline
            )
            recapText = result.recap
            recapProgressHeadline = result.progressHeadline
            recapError = nil
            audiobook.storeProgressRecap(
                text: result.recap,
                headline: result.progressHeadline,
                anchorTrackIndex: anchorTrackIndex,
                anchorTime: anchorTime
            )
            try? modelContext?.save()
            onSuccessfulRecap?()
        } catch let error as RecapError {
            recapError = error.errorDescription
        } catch {
            recapError = RecapError.generationFailed.errorDescription
        }
    }
```

- [x] **Step 10.5: Run tests**

Run: `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: all AudiobookDetailViewModel tests PASS, including pre-existing recap-persistence tests.

- [x] **Step 10.6: Commit**

```bash
git add Pageless/ViewModels/AudiobookDetailViewModel.swift PagelessTests/Mocks/MockRecapService.swift PagelessTests/ViewModelTests/AudiobookDetailViewModelTests.swift
git commit -m "feat(ai): permission-free recap pipeline with legacy fallback and friendly error copy"
```

---

### Task 11: PlayerView prewarm hook + capability gate relax

**Files:**
- Modify: `Pageless/Views/PlayerView.swift` (body modifier chain, near `.background(Color.cream.ignoresSafeArea())`)
- Modify: `Pageless/Services/AppleIntelligenceCapability.swift:50-55,92-94`

- [x] **Step 11.1: Prewarm when the player appears with smart save enabled**

In `PlayerView`'s body modifier chain (after `.contentShape(Rectangle())`), add:

```swift
        .onAppear {
            if useSmartSave { viewModel.prewarmSmartSave() }
        }
        .onChange(of: useSmartSave) { _, enabled in
            if enabled { viewModel.prewarmSmartSave() }
        }
```

- [x] **Step 11.2: Relax the capability gate**

In `AppleIntelligenceCapability`, the primary transcription path no longer uses
SFSpeechRecognizer, so model availability alone gates smart naming:

```swift
    /// Whether the foundational local model is available for Smart Moment Naming.
    /// Transcription uses the iOS 26 SpeechAnalyzer (with an SFSpeechRecognizer
    /// fallback), so speech-recognizer availability is no longer a hard requirement.
    static var isSmartNamingAvailable: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }
```

And in `unavailabilityReason`, the `.available` case becomes:

```swift
        case .available:
            return nil
```

Remove the now-unused `isSpeechRecognitionAvailable` private property.

- [x] **Step 11.3: Build + full test pass**

Run: `mcp__XcodeBuildMCP__build_device`, then `mcp__XcodeBuildMCP__test_device` with `extraArgs: ["-parallel-testing-enabled", "NO"]`.
Expected: BUILD SUCCEEDED; all tests PASS.

- [x] **Step 11.4: Commit**

```bash
git add Pageless/Views/PlayerView.swift Pageless/Services/AppleIntelligenceCapability.swift
git commit -m "feat(ai): prewarm model on player open; gate smart naming on model availability only"
```

---

### Task 12: On-device verification (manual, with Andrei)

No code. Run the app on the iPhone 15 Pro via `mcp__XcodeBuildMCP__build_run_device` and verify with the user:

- [ ] Smart save on a downloaded book: tap Smart Save Moment → sheet should appear in ~4–8 s with name/note/categories/mood/quote populated; quote text must appear verbatim in the transcript.
- [ ] Smart save on a passage that previously triggered "Apple says it will not do it" (violent/romantic fiction): should now produce an analysis, not the unsafe warning.
- [ ] Recap from book detail: sparkles button → recap + headline; verify persisted recap re-hydrates after navigating away and back.
- [ ] Airplane mode: smart save and recap still work on a downloaded book (everything is on-device).
- [ ] First-run check: if the device asks to download speech assets on first smart save, confirm the one-time wait, then re-run for speed.
- [ ] Confirm no speech-permission dialog appears on a fresh install when using smart save (primary path needs none). (Voice permissions are still primed at launch for CarPlay — that's separate and expected.)

If smart save feels slow on the *very first* tap after install, that's the one-time asset install — acceptable; subsequent saves should hit the fast path.

---

## Post-implementation

- Update `CLAUDE.md` "AI & On-Device Intelligence" section: SpeechAnalyzer primary transcription, permissive guardrails rationale, prewarm hook, verified quotes. (Per repo policy, no external-docs changes needed: no permission, network, or IAP behavior changed — smart save stops *requiring* speech permission but the usage descriptions remain for CarPlay voice search.)
- Commit docs:

```bash
git add CLAUDE.md docs/superpowers/specs/2026-06-11-ai-pipeline-v2-design.md docs/superpowers/plans/2026-06-11-ai-pipeline-v2.md
git commit -m "docs: AI pipeline v2 spec, plan, and CLAUDE.md updates"
```
