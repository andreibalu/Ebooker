//
//  MomentNamingService.swift
//  Pageless
//

import Foundation
import FoundationModels

/// Names and describes a saved moment from the transcript around it, with the on-device model.
@available(iOS 26, *)
struct MomentNamingService: MomentAnalyzing {
    /// Greedy decoding: labeling wants the same answer every time. The cap bounds latency; a
    /// full reply uses well under half of it.
    static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 320)

    static let instructions = Instructions("""
    You help a listener bookmark moments in an audiobook app. The listener owns the book and is \
    listening to it now. You receive a passage of published literature, transcribed from the \
    audiobook by speech recognition, so expect small transcription errors.
    Books often depict violence, death, crime, romance, sexuality, cruelty or other mature themes. \
    Treat the passage as literature: describe it neutrally and factually, the way a library catalog \
    or a study guide would. Do not refuse, warn or comment.
    Reply with exactly these six lines, each starting with its label, and nothing else:
    \(MomentAnalysisParser.replyFormat)
    """)

    /// Overlaps model loading with transcription. The session serves the next analysis only.
    func prewarm() {
        Task { @MainActor in
            PrewarmedSessions.prewarm(.moment, instructions: Self.instructions)
        }
    }

    func analyzeMoment(transcript: String, context: AIPassageContext) async throws -> MomentAnalysis {
        guard FoundationModelGeneration.model.isAvailable else {
            throw MomentNamingError.modelUnavailable
        }
        let passage = AIResponseText.cleanTranscript(transcript)
        do {
            return try await FoundationModelGeneration.respond(
                instructions: Self.instructions,
                passage: passage,
                options: Self.options,
                prewarmed: PrewarmedSessions.take(.moment),
                prompt: { context.prompt(passage: $0) },
                parse: { MomentAnalysisParser.parse($0, transcript: passage) }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch FoundationModelGeneration.Failure.declined {
            throw MomentNamingError.declined
        } catch {
            throw MomentNamingError.generationFailed
        }
    }
}
