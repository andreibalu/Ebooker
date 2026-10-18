//
//  FoundationModelGeneration.swift
//  Pageless
//

import Foundation
import FoundationModels

/// The one path every on-device generation takes: the shared model, a plain-text request,
/// typed failures and a single retry.
@available(iOS 26, *)
enum FoundationModelGeneration {
    /// Permissive guardrails let the model transform the user's own content, such as a novel's
    /// violence or romance. They apply only to `String` responses: guided `@Generable` output
    /// keeps the default guardrails, which reject about half of ordinary fiction passages. So
    /// every request here asks for text and parses it.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    enum Failure: Error, Equatable {
        /// Guardrail violation or refusal, after one retry on a shorter passage.
        case declined
        /// Any other generation failure (unreadable reply, unsupported locale, …), after one
        /// retry where one can help.
        case failed
    }

    private enum RetryAction {
        case retryWithPassageTail
        case retryAfterDelay(Duration)
    }

    private static let defaultRetryDelay = Duration.milliseconds(700)

    /// Sends `prompt(passage)` and parses the reply. A refusal reply counts as `.declined`,
    /// any other reply `parse` rejects as `.failed`. The first attempt may use a prewarmed
    /// session; a retry always starts a fresh one, because a failed session's context is polluted.
    static func respond<T>(
        instructions: Instructions,
        passage: String,
        options: GenerationOptions,
        prewarmed: LanguageModelSession? = nil,
        prompt: (String) -> String,
        parse: (String) -> T?
    ) async throws -> T {
        var prewarmed = prewarmed
        return try await run(transcript: passage) { attemptPassage in
            let session = prewarmed ?? LanguageModelSession(model: model, instructions: instructions)
            prewarmed = nil
            let reply = try await session.respond(to: Prompt(prompt(attemptPassage)), options: options).content
            if let value = parse(reply) { return value }
            throw AIResponseText.isRefusal(reply) ? Failure.declined : Failure.failed
        }
    }

    /// Runs `attempt`, mapping Foundation Models errors to `Failure` and retrying once:
    /// - declined or context overflow: on the second half of the passage (the most recent audio
    ///   matters most, and the shorter text often no longer trips the refusal);
    /// - rate limited or concurrent requests: on the same passage after a short delay.
    /// An unreadable reply or an unsupported request fails without a retry, since greedy
    /// sampling would repeat it.
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

            let retryTranscript: String
            switch retryAction(for: error) {
            case .retryWithPassageTail:
                let tail = passageTail(transcript)
                guard !tail.isEmpty else { throw failure(for: error) }
                retryTranscript = tail
            case .retryAfterDelay(let delay):
                try await Task.sleep(for: delay)
                retryTranscript = transcript
            case nil:
                throw failure(for: error)
            }

            try Task.checkCancellation()
            do {
                let result = try await attempt(retryTranscript)
                try Task.checkCancellation()
                return result
            } catch {
                try rethrowCancellation(after: error)
                throw failure(for: error)
            }
        }
    }

    /// The second half of the passage, widened back to the start of the word it cuts.
    static func passageTail(_ passage: String) -> String {
        let middle = passage.index(passage.endIndex, offsetBy: -(passage.count / 2))
        let start = passage[..<middle].lastIndex(where: \.isWhitespace).map { passage.index(after: $0) } ?? middle
        return String(passage[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rethrowCancellation(after error: Error) throws {
        if error is CancellationError || Task.isCancelled {
            throw CancellationError()
        }
    }

    private static func failure(for error: Error) -> Failure {
        if let failure = error as? Failure { return failure }
        return isDeclined(error) ? .declined : .failed
    }

    private static func isDeclined(_ error: Error) -> Bool {
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        if #available(iOS 27, *), let languageModelError = error as? LanguageModelError {
            switch languageModelError {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        return false
    }

    private static func retryAction(for error: Error) -> RetryAction? {
        if let failure = error as? Failure {
            return failure == .declined ? .retryWithPassageTail : nil
        }
        if isDeclined(error) { return .retryWithPassageTail }

        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .exceededContextWindowSize:
                return .retryWithPassageTail
            case .rateLimited, .concurrentRequests:
                return .retryAfterDelay(defaultRetryDelay)
            default:
                return nil
            }
        }

        if #available(iOS 27, *) {
            return retryActionOnIOS27(for: error)
        }
        return nil
    }

    @available(iOS 27, *)
    private static func retryActionOnIOS27(for error: Error) -> RetryAction? {
        if let languageModelError = error as? LanguageModelError {
            switch languageModelError {
            case .contextSizeExceeded:
                return .retryWithPassageTail
            case .rateLimited(let info):
                // Wait for the reset the system reports, within reason.
                guard let reset = info.resetDate else { return .retryAfterDelay(defaultRetryDelay) }
                let seconds = min(max(reset.timeIntervalSinceNow, 0.7), 3)
                return .retryAfterDelay(.milliseconds(Int(seconds * 1000)))
            case .guardrailViolation,
                 .refusal,
                 .unsupportedCapability,
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
                return .retryAfterDelay(defaultRetryDelay)
            case .transcriptMutationWhileResponding:
                return nil
            @unknown default:
                return nil
            }
        }

        // Asset failures (`SystemLanguageModel.Error`) are terminal for this operation.
        return nil
    }
}

/// Sessions loaded ahead of a likely request, one per feature. Each serves exactly one
/// request: sessions are multi-turn, so reuse would carry the previous passage's context.
@available(iOS 26, *)
@MainActor
enum PrewarmedSessions {
    enum Purpose: Hashable {
        case moment
        case recap
    }

    private static var sessions: [Purpose: LanguageModelSession] = [:]

    static func prewarm(_ purpose: Purpose, instructions: Instructions) {
        guard FoundationModelGeneration.model.isAvailable, sessions[purpose] == nil else { return }
        let session = LanguageModelSession(model: FoundationModelGeneration.model, instructions: instructions)
        session.prewarm()
        sessions[purpose] = session
    }

    static func take(_ purpose: Purpose) -> LanguageModelSession? {
        sessions.removeValue(forKey: purpose)
    }
}
