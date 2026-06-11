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
