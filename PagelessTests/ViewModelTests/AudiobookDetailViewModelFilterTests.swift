//
//  AudiobookDetailViewModelFilterTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct AudiobookDetailViewModelFilterTests {
    private func makeViewModel(audiobook: Audiobook) -> AudiobookDetailViewModel {
        AudiobookDetailViewModel(
            audiobook: audiobook,
            transcription: MockTranscriptionService(),
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService()
        )
    }

    @Test func combinedCategoryAndMoodFilter() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "filter-combo", totalDuration: 100)
        context.insert(book)

        let both = Moment(
            trackIndex: 0,
            time: 1,
            label: "Both",
            audiobook: book,
            categories: [.dialogue],
            mood: .tense
        )
        let categoryOnly = Moment(
            trackIndex: 0,
            time: 2,
            label: "Cat",
            audiobook: book,
            categories: [.dialogue],
            mood: .funny
        )
        context.insert(both)
        context.insert(categoryOnly)
        book.moments.append(contentsOf: [both, categoryOnly])

        let vm = makeViewModel(audiobook: book)
        vm.filterCategories = [.dialogue]
        vm.filterMoods = [.tense]
        #expect(vm.filteredMoments.count == 1)
        #expect(vm.filteredMoments.first?.id == both.id)
    }
}
