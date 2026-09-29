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

    @Test func obtainTranscriptUsesBacktrackHeavyWindow() async throws {
        let segment = MockSegmentTranscriber()
        let vm = makeViewModel(segmentTranscriber: segment)

        _ = try await vm.obtainTranscript(
            fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), currentTime: 100, duration: 600
        )

        #expect(segment.lastRange?.start == 25)   // 100 − 75
        #expect(segment.lastRange?.end == 115)    // 100 + 15
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
}
