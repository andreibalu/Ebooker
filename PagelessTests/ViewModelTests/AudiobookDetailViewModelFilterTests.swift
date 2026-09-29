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

    @Test func filterBySingleCategoryRetainsMatchingMoments() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "filter-cat", totalDuration: 100)
        context.insert(book)

        let m1 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, categories: [.dialogue])
        m1.createdAt = Date(timeIntervalSince1970: 100)
        let m2 = Moment(trackIndex: 0, time: 2, label: "B", audiobook: book, categories: [.action])
        m2.createdAt = Date(timeIntervalSince1970: 200)
        context.insert(m1)
        context.insert(m2)
        book.moments.append(contentsOf: [m1, m2])

        let vm = makeViewModel(audiobook: book)
        vm.filterCategories = [.dialogue]
        #expect(vm.filteredMoments.count == 1)
        #expect(vm.filteredMoments.first?.id == m1.id)
    }

    @Test func filterByCharacterIsCaseInsensitive() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "filter-char", totalDuration: 100)
        context.insert(book)

        let m1 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, characters: ["Alice"])
        let m2 = Moment(trackIndex: 0, time: 2, label: "B", audiobook: book, characters: ["Bob"])
        context.insert(m1)
        context.insert(m2)
        book.moments.append(contentsOf: [m1, m2])

        let vm = makeViewModel(audiobook: book)
        vm.filterCharacters = ["alice"]
        #expect(vm.filteredMoments.count == 1)
        #expect(vm.filteredMoments.first?.id == m1.id)
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

    @Test func hasAiAnalyzedMomentsReturnsTrueWithCategoriesOrMood() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let categorized = Audiobook(title: "F", author: "", folderName: "ai-cat", totalDuration: 100)
        let moody = Audiobook(title: "F", author: "", folderName: "ai-mood", totalDuration: 100)
        context.insert(categorized)
        context.insert(moody)
        let m1 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: categorized, categories: [.worldBuilding])
        let m2 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: moody, mood: .inspirational)
        context.insert(m1)
        context.insert(m2)
        categorized.moments.append(m1)
        moody.moments.append(m2)

        #expect(makeViewModel(audiobook: categorized).hasAiAnalyzedMoments == true)
        #expect(makeViewModel(audiobook: moody).hasAiAnalyzedMoments == true)
    }
}
