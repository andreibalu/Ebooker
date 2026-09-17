//
//  FoundationModelGenerationTests.swift
//  PagelessTests
//

import Foundation
import FoundationModels
import Testing
@testable import Pageless

@MainActor
struct FoundationModelGenerationTests {
    @Test func cancellationBeforeFirstAttemptPropagatesWithoutInvokingAttempt() async throws {
        guard #available(iOS 26, *) else { return }

        var attempts = 0
        let task = Task { @MainActor in
            try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                attempts += 1
                return 1
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancellation should propagate before generation starts")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error after cancellation: \(error)")
        }

        #expect(attempts == 0)
    }

    @Test func cancellationDuringAttemptPropagatesWithoutRetry() async throws {
        guard #available(iOS 26, *) else { return }

        let (startedStream, startedContinuation) = AsyncStream<Void>.makeStream()
        var attempts = 0
        let task = Task { @MainActor in
            try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                attempts += 1
                startedContinuation.yield(())
                try await Task.sleep(for: .seconds(60))
                return 1
            }
        }

        for await _ in startedStream {
            break
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancellation should propagate from an in-flight attempt")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error after cancellation: \(error)")
        }

        #expect(attempts == 1)
    }

    @Test func cancellationDuringRetryDelayPropagatesWithoutSecondAttempt() async throws {
        guard #available(iOS 26, *) else { return }

        let (startedStream, startedContinuation) = AsyncStream<Void>.makeStream()
        var attempts = 0
        let rateLimit = LanguageModelSession.GenerationError.rateLimited(
            .init(debugDescription: "test rate limit")
        )
        let task = Task { @MainActor in
            try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                attempts += 1
                startedContinuation.yield(())
                throw rateLimit
            }
        }

        for await _ in startedStream {
            break
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancellation should stop the retry delay")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error after cancellation: \(error)")
        }

        #expect(attempts == 1)
    }

    @Test func iOS26GuardrailAndContextErrorsKeepTheirPolicy() async throws {
        guard #available(iOS 26, *) else { return }

        do {
            _ = try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                throw LanguageModelSession.GenerationError.guardrailViolation(
                    .init(debugDescription: "test guardrail")
                )
            }
            Issue.record("Guardrail violations should map to unsafe content")
        } catch FoundationModelGeneration.Failure.unsafeContent {
            // Expected.
        }

        var attempts = 0
        let contextOverflow = LanguageModelSession.GenerationError.exceededContextWindowSize(
            .init(debugDescription: "test context overflow")
        )
        let result = try await FoundationModelGeneration.run(transcript: "abcdefghij") { transcript -> Int in
            attempts += 1
            if attempts == 1 {
                throw contextOverflow
            }
            #expect(transcript == "fghij")
            return attempts
        }

        #expect(result == 2)
        #expect(attempts == 2)
    }

    @Test func iOS27GuardrailAndRefusalMapToUnsafeContent() async throws {
        guard #available(iOS 27, *) else { return }

        let errors = [
            LanguageModelError.guardrailViolation(.init(debugDescription: "test guardrail")),
            LanguageModelError.refusal(.init(explanation: "test refusal", debugDescription: "test refusal")),
        ]

        for error in errors {
            do {
                _ = try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                    throw error
                }
                Issue.record("Unsafe content should not be retried")
            } catch FoundationModelGeneration.Failure.unsafeContent {
                // Expected.
            }
        }
    }

    @Test func iOS27ContextOverflowRetriesWithTranscriptTail() async throws {
        guard #available(iOS 27, *) else { return }

        var attempts = 0
        let contextOverflow = LanguageModelError.contextSizeExceeded(
            .init(contextSize: 4_096, tokenCount: 4_097, debugDescription: "test context overflow")
        )
        let result = try await FoundationModelGeneration.run(transcript: "abcdefghij") { transcript -> Int in
            attempts += 1
            if attempts == 1 {
                throw contextOverflow
            }
            #expect(transcript == "fghij")
            return attempts
        }

        #expect(result == 2)
        #expect(attempts == 2)
    }

    @Test func iOS27RateLimitAndConcurrentRequestRetryOnce() async throws {
        guard #available(iOS 27, *) else { return }

        let errors: [any Error] = [
            LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "test rate limit")),
            LanguageModelSession.Error.concurrentRequests,
        ]

        for error in errors {
            var attempts = 0
            let result = try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                attempts += 1
                if attempts == 1 {
                    throw error
                }
                return attempts
            }
            #expect(result == 2)
            #expect(attempts == 2)
        }
    }

    @Test func iOS27UnsupportedGenerationFailsWithoutRetry() async throws {
        guard #available(iOS 27, *) else { return }

        var attempts = 0
        let unsupported = LanguageModelError.unsupportedLanguageOrLocale(
            .init(languageCode: Locale.LanguageCode("zz"), debugDescription: "test unsupported locale")
        )
        do {
            _ = try await FoundationModelGeneration.run(transcript: "excerpt") { _ -> Int in
                attempts += 1
                throw unsupported
            }
            Issue.record("Unsupported generation should fail")
        } catch FoundationModelGeneration.Failure.failed {
            // Expected.
        }

        #expect(attempts == 1)
    }
}
