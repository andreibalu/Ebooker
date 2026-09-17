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

    private enum RetryAction {
        case unsafeContent
        case retryWithTranscriptTail
        case retryWithOriginalTranscript
    }

    /// Runs `attempt`, mapping Foundation Models errors to `Failure` and retrying
    /// once on transient errors. On a context overflow the retry receives the
    /// second half of the transcript (most recent audio matters most).
    /// `attempt` must create a fresh session per call — a failed session's context
    /// is polluted.
    static func run<T>(
        transcript: String,
        attempt: (String) async throws -> T
    ) async throws -> T {
        do {
            try Task.checkCancellation()
            let result = try await attempt(transcript)
            try Task.checkCancellation()
            return result
        } catch {
            try rethrowCancellation(after: error)

            guard let action = retryAction(for: error) else {
                throw Failure.failed
            }

            let retryTranscript: String
            switch action {
            case .unsafeContent:
                throw Failure.unsafeContent
            case .retryWithTranscriptTail:
                retryTranscript = String(transcript.suffix(transcript.count / 2))
            case .retryWithOriginalTranscript:
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                retryTranscript = transcript
            }

            try Task.checkCancellation()
            do {
                let result = try await attempt(retryTranscript)
                try Task.checkCancellation()
                return result
            } catch {
                try rethrowCancellation(after: error)
                throw terminalFailure(for: error)
            }
        }
    }

    private static func rethrowCancellation(after error: Error) throws {
        if error is CancellationError || Task.isCancelled {
            throw CancellationError()
        }
    }

    private static func retryAction(for error: Error) -> RetryAction? {
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .guardrailViolation, .refusal:
                return .unsafeContent
            case .exceededContextWindowSize:
                return .retryWithTranscriptTail
            case .rateLimited, .concurrentRequests:
                return .retryWithOriginalTranscript
            default:
                return nil
            }
        }

        if #available(iOS 27, *) {
            return retryActionOnIOS27(for: error)
        }
        return nil
    }

    private static func terminalFailure(for error: Error) -> Failure {
        guard let action = retryAction(for: error) else { return .failed }
        if case .unsafeContent = action { return .unsafeContent }
        return .failed
    }

    @available(iOS 27, *)
    private static func retryActionOnIOS27(for error: Error) -> RetryAction? {
        if let languageModelError = error as? LanguageModelError {
            switch languageModelError {
            case .guardrailViolation, .refusal:
                return .unsafeContent
            case .contextSizeExceeded:
                return .retryWithTranscriptTail
            case .rateLimited:
                return .retryWithOriginalTranscript
            case .unsupportedCapability,
                 .unsupportedTranscriptContent,
                 .unsupportedGenerationGuide,
                 .unsupportedLanguageOrLocale,
                 .timeout:
                return nil
            @unknown default:
                return nil
            }
        }

        if let sessionError = error as? LanguageModelSession.Error {
            switch sessionError {
            case .concurrentRequests:
                return .retryWithOriginalTranscript
            case .transcriptMutationWhileResponding:
                return nil
            @unknown default:
                return nil
            }
        }

        // Asset failures are terminal for this operation. They are kept distinct
        // from generation failures by the SDK, but neither should trigger a retry
        // of the same session request.
        if error is SystemLanguageModel.Error {
            return nil
        }

        return nil
    }

}
