//
//  RecapService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Uses the on-device foundation model to generate a brief recap of recent audiobook events.
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

    /// Generates a recap from a transcript of recent audio.
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
