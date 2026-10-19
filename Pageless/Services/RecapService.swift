//
//  RecapService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Writes a short recap of the audio before the listener's saved position, with the on-device model.
@available(iOS 26, *)
struct RecapService: RecapProviding {
    static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 240)

    /// One set of instructions for both callers, so a single prewarmed session serves either.
    /// The headline is always written (it costs a few tokens) and dropped when not requested.
    static let instructions = Instructions("""
    You help a listener pick up an audiobook where they left off. The listener owns the book. You \
    receive the last few minutes they heard, a passage of published literature transcribed from the \
    audiobook by speech recognition, so expect small transcription errors.
    Books often depict violence, death, crime, romance, sexuality, cruelty or other mature themes. \
    Treat the passage as literature: summarize it neutrally and factually, the way a study guide would. \
    Use only what the passage says. Do not refuse, warn or comment.
    Reply with exactly these two lines, each starting with its label, and nothing else:
    Headline: a 2 to 4 word phrase naming where the listener left off
    Recap: two sentences on what just happened, naming the characters involved
    """)

    func prewarm() {
        Task { @MainActor in
            PrewarmedSessions.prewarm(.recap, instructions: Self.instructions)
        }
    }

    func generateRecap(
        transcript: String,
        context: AIPassageContext,
        includeProgressHeadline: Bool
    ) async throws -> RecapGenerationResult {
        guard FoundationModelGeneration.model.isAvailable else {
            throw RecapError.modelUnavailable
        }
        let passage = AIResponseText.cleanTranscript(transcript)
        do {
            var result = try await FoundationModelGeneration.respond(
                instructions: Self.instructions,
                passage: passage,
                options: Self.options,
                prewarmed: PrewarmedSessions.take(.recap),
                prompt: { context.prompt(passage: $0) },
                parse: Self.parse
            )
            if !includeProgressHeadline { result.progressHeadline = nil }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch FoundationModelGeneration.Failure.declined {
            throw RecapError.declined
        } catch {
            throw RecapError.generationFailed
        }
    }

    /// Nil for a refusal or a reply without recap prose. Prose without its label still counts.
    static func parse(_ reply: String) -> RecapGenerationResult? {
        guard !AIResponseText.isRefusal(reply) else { return nil }
        let fields = AIResponseText.labeledFields(in: reply, labels: ["Headline", "Recap"], overflowLabel: "Recap")
        let recap = AIResponseText.capitalizingFirstLetter(AIResponseText.trimToCompleteSentences(fields["recap"] ?? ""))
        guard !recap.isEmpty, !AIResponseText.isRefusal(recap) else { return nil }
        let headline = sanitizeHeadline(fields["headline"] ?? "")
        return RecapGenerationResult(recap: recap, progressHeadline: headline.isEmpty ? nil : headline)
    }

    /// A short label starting with a capital: the headline replaces a section title, and the
    /// model often writes it in lowercase. The prompt asks for 2 to 4 words; one word of slack
    /// keeps a slight overshoot ("Dusk at the river mouth") whole instead of cutting it short.
    static func sanitizeHeadline(_ raw: String) -> String {
        AIResponseText.capitalizingFirstLetter(AIResponseText.cleanTitle(raw, maxWords: 5))
    }
}
