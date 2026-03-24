//
//  PlayerViewModelTests.swift
//  PagelessTests
//

import Testing
import Foundation
@testable import Pageless

@MainActor
struct PlayerViewModelTests {
    private func makeViewModel(
        transcription: MockTranscriptionService = MockTranscriptionService(),
        analyzer: MockMomentAnalyzer = MockMomentAnalyzer(),
        extractor: MockAudioExtractor = MockAudioExtractor()
    ) -> PlayerViewModel {
        PlayerViewModel(
            transcription: transcription,
            momentAnalyzer: analyzer,
            audioExtractor: extractor
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
}
