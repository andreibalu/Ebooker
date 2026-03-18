//
//  AudiobookDetailViewModelTests.swift
//  EbookerTests
//

import Testing
import Foundation
@testable import Ebooker

@MainActor
struct AudiobookDetailViewModelTests {
    private func makeAudiobook() -> Audiobook {
        Audiobook(title: "Test Book", author: "Author", folderName: "test-folder", totalDuration: 3600)
    }

    private func makeViewModel(audiobook: Audiobook? = nil) -> AudiobookDetailViewModel {
        let book = audiobook ?? makeAudiobook()
        return AudiobookDetailViewModel(
            audiobook: book,
            transcription: MockTranscriptionService(),
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService()
        )
    }

    @Test func initialFilterStateIsEmpty() {
        let vm = makeViewModel()

        #expect(vm.filterCategories.isEmpty)
        #expect(vm.filterCharacters.isEmpty)
        #expect(vm.filterMoods.isEmpty)
        #expect(vm.hasActiveFilters == false)
    }

    @Test func hasActiveFiltersReflectsState() {
        let vm = makeViewModel()

        vm.filterCategories.insert(.dialogue)
        #expect(vm.hasActiveFilters == true)

        vm.clearFilters()
        #expect(vm.hasActiveFilters == false)
    }

    @Test func clearFiltersRemovesAll() {
        let vm = makeViewModel()

        vm.filterCategories = [.dialogue, .action]
        vm.filterCharacters = ["alice"]
        vm.filterMoods = [.tense]

        vm.clearFilters()

        #expect(vm.filterCategories.isEmpty)
        #expect(vm.filterCharacters.isEmpty)
        #expect(vm.filterMoods.isEmpty)
    }

    @Test func initialRecapStateIsNil() {
        let vm = makeViewModel()

        #expect(vm.isLoadingRecap == false)
        #expect(vm.recapText == nil)
        #expect(vm.recapError == nil)
    }

    @Test func hasAiAnalyzedMomentsReturnsFalseWhenEmpty() {
        let vm = makeViewModel()

        #expect(vm.hasAiAnalyzedMoments == false)
    }

    @Test func filteredMomentsReturnsAllWhenNoFilters() {
        let vm = makeViewModel()

        // No moments on the audiobook, so filtered list should be empty
        #expect(vm.filteredMoments.isEmpty)
    }
}
