//
//  PlayerViewModelTests.swift
//  PagelessTests
//

import Testing
import Foundation
import Speech
@testable import Pageless

@MainActor
struct PlayerViewModelTests {
    private func makeViewModel(
        transcription: MockTranscriptionService = MockTranscriptionService(),
        analyzer: MockMomentAnalyzer = MockMomentAnalyzer(),
        extractor: MockAudioExtractor = MockAudioExtractor(),
        segmentTranscriber: any SegmentTranscribing = MockSegmentTranscriber()
    ) -> PlayerViewModel {
        PlayerViewModel(
            transcription: transcription,
            momentAnalyzer: analyzer,
            audioExtractor: extractor,
            segmentTranscriber: segmentTranscriber
        )
    }

    // MARK: - obtainTranscript

    @Test func obtainTranscriptUsesPrimaryPathWithoutAuthorization() async throws {
        let transcription = MockTranscriptionService()
        let segment = MockSegmentTranscriber()
        segment.transcriptToReturn = "primary transcript"
        let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

        let result = try await vm.obtainTranscript(
            fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
        )

        #expect(result == "primary transcript")
        #expect(transcription.authorizationRequestCount == 0)
        #expect(transcription.transcribeCallCount == 0)
    }

    @Test func obtainTranscriptClampsWindowToTrackBounds() async throws {
        let segment = MockSegmentTranscriber()
        let vm = makeViewModel(segmentTranscriber: segment)

        _ = try await vm.obtainTranscript(
            fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 10, duration: 18
        )

        #expect(segment.lastRange?.start == 0)
        #expect(segment.lastRange?.end == 18)
    }

    @Test func obtainTranscriptFallsBackToLegacyWhenPrimaryThrows() async throws {
        let transcription = MockTranscriptionService()
        transcription.transcriptToReturn = "legacy transcript"
        let segment = MockSegmentTranscriber()
        segment.shouldThrow = true
        let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

        let result = try await vm.obtainTranscript(
            fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
        )

        #expect(result == "legacy transcript")
        #expect(transcription.authorizationRequestCount == 1)
    }

    @Test func obtainTranscriptPropagatesCancellationWithoutLegacyFallback() async throws {
        let transcription = MockTranscriptionService()
        let segment = BlockingSegmentTranscriber()
        let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

        let task = Task { @MainActor in
            try await vm.obtainTranscript(
                fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
            )
        }
        await segment.waitUntilStarted()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancellation should propagate from the primary path")
        } catch is CancellationError {
            // Expected: cancellation must not be interpreted as a primary failure.
        } catch {
            Issue.record("Unexpected error after cancellation: \(error)")
        }

        #expect(transcription.authorizationRequestCount == 0)
        #expect(transcription.transcribeCallCount == 0)
    }

    @Test func obtainTranscriptReturnsNilWhenPrimaryFailsAndAuthDenied() async throws {
        let transcription = MockTranscriptionService()
        transcription.authorizationStatus = .denied
        let segment = MockSegmentTranscriber()
        segment.shouldThrow = true
        let vm = makeViewModel(transcription: transcription, segmentTranscriber: segment)

        let result = try await vm.obtainTranscript(
            fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
        )

        #expect(result == nil)
        #expect(transcription.transcribeCallCount == 0)
    }

    // MARK: - applyAnalysis

    private let context = AIPassageContext(bookTitle: "Book", author: "Author", chapterTitle: "Chapter 3")
    private let transcript = "Elizabeth opened the letter. Elizabeth read it twice."

    @Test func applyAnalysisPopulatesPendingFields() async {
        let analyzer = MockMomentAnalyzer()
        let vm = makeViewModel(analyzer: analyzer)

        await vm.applyAnalysis(transcript: transcript, context: context, savedTime: 42)

        #expect(analyzer.lastContext == context)
        #expect(vm.momentNameInput == "Test Moment")
        #expect(vm.momentNoteInput == "Test note")
        #expect(vm.pendingMomentAiGenerated == true)
        #expect(vm.pendingCategories == [.dialogue])
        #expect(vm.pendingQuoteLine == "A test quote")
        #expect(vm.pendingCharacters == ["Alice"])
        #expect(vm.pendingMood == .mysterious)
        #expect(vm.pendingMomentTime == 42)
        #expect(vm.pendingSmartSaveNotice == nil)
    }

    /// The owner's bug: a declined passage opened the sheet as "Saved Moment" under a warning
    /// that the audiobook was unsafe. Every failure now yields a fallback name and a calm notice.
    @Test func applyAnalysisFallsBackToANamedDraftOnAnyFailure() async {
        for error in [MomentNamingError.declined, .generationFailed, .modelUnavailable] {
            let analyzer = MockMomentAnalyzer()
            analyzer.errorToThrow = error
            let vm = makeViewModel(analyzer: analyzer)

            await vm.applyAnalysis(transcript: transcript, context: context, savedTime: 42)

            #expect(vm.momentNameInput == "Elizabeth in Chapter 3")
            #expect(vm.pendingSmartSaveNotice == .couldNotSummarize)
            #expect(vm.pendingMomentTranscript == transcript)
            #expect(vm.pendingMomentTime == 42)
            #expect(vm.pendingMomentAiGenerated == false)
        }
    }
}
