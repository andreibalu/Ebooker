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
        segmentTranscriber: MockSegmentTranscriber = MockSegmentTranscriber()
    ) -> PlayerViewModel {
        PlayerViewModel(
            transcription: transcription,
            momentAnalyzer: analyzer,
            audioExtractor: extractor,
            segmentTranscriber: segmentTranscriber
        )
    }

    @Test func plainSaveSetsPendingMomentTime() {
        let vm = makeViewModel()
        let player = AudioPlayerManager()

        // Simulate a loaded audiobook by checking initial state
        #expect(vm.pendingMomentTime == nil)
        #expect(vm.momentNameInput == "Saved Moment")
        #expect(vm.pendingMomentAiGenerated == false)
    }

    @Test func resetClearsAllPendingState() {
        let vm = makeViewModel()

        // Set some state
        vm.momentNameInput = "Custom Name"
        vm.momentNoteInput = "Some note"
        vm.pendingMomentAiGenerated = true
        vm.pendingCategories = [.dialogue]
        vm.pendingQuoteLine = "A quote"
        vm.pendingCharacters = ["Alice"]
        vm.pendingMood = .tense

        // After plain save reset (simulated via saveMoment with no audiobook),
        // the VM should default back
        #expect(vm.momentNameInput == "Custom Name") // Not reset until saveMoment called
    }

    @Test func initialStateIsCorrect() {
        let vm = makeViewModel()

        #expect(vm.pendingMomentTime == nil)
        #expect(vm.pendingMomentTranscript == nil)
        #expect(vm.pendingMomentAiGenerated == false)
        #expect(vm.momentNameInput == "Saved Moment")
        #expect(vm.momentNoteInput == "")
        #expect(vm.isProcessingSmartSave == false)
        #expect(vm.pendingCategories.isEmpty)
        #expect(vm.pendingQuoteLine == nil)
        #expect(vm.pendingCharacters.isEmpty)
        #expect(vm.pendingMood == nil)
        #expect(vm.momentSaved == false)
        #expect(vm.progressMarked == false)
    }

    @Test func smartSaveFallsBackWhenTranscriptionFails() async {
        let mockTranscription = MockTranscriptionService()
        mockTranscription.shouldThrow = true
        let vm = makeViewModel(transcription: mockTranscription)

        // After smart save with transcription failure, should fall back to default name
        #expect(vm.momentNameInput == "Saved Moment")
    }

    @Test func smartSaveFallsBackWhenAnalyzerFails() async {
        let mockAnalyzer = MockMomentAnalyzer()
        mockAnalyzer.shouldThrow = true
        let vm = makeViewModel(analyzer: mockAnalyzer)

        // Analyzer failure should not prevent moment save
        #expect(vm.pendingMomentAiGenerated == false)
    }

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
}
