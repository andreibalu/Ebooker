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
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
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

    @Test func filterByCategoryExcludesNonMatching() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "filter-ex", totalDuration: 100)
        context.insert(book)

        let m1 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, categories: [.tension])
        let m2 = Moment(trackIndex: 0, time: 2, label: "B", audiobook: book, categories: [.romance])
        context.insert(m1)
        context.insert(m2)
        book.moments.append(contentsOf: [m1, m2])

        let vm = makeViewModel(audiobook: book)
        vm.filterCategories = [.humor]
        #expect(vm.filteredMoments.isEmpty)
    }

    @Test func filterByCharacterIsCaseInsensitive() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
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

    @Test func filterByMoodRetainsMatch() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "filter-mood", totalDuration: 100)
        context.insert(book)

        let m1 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, mood: .dramatic)
        let m2 = Moment(trackIndex: 0, time: 2, label: "B", audiobook: book, mood: .peaceful)
        context.insert(m1)
        context.insert(m2)
        book.moments.append(contentsOf: [m1, m2])

        let vm = makeViewModel(audiobook: book)
        vm.filterMoods = [.dramatic]
        #expect(vm.filteredMoments.count == 1)
        #expect(vm.filteredMoments.first?.id == m1.id)
    }

    @Test func filterByMoodExcludesNonMatch() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "filter-mood-ex", totalDuration: 100)
        context.insert(book)

        let m1 = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, mood: .sad)
        context.insert(m1)
        book.moments.append(m1)

        let vm = makeViewModel(audiobook: book)
        vm.filterMoods = [.funny]
        #expect(vm.filteredMoments.isEmpty)
    }

    @Test func combinedCategoryAndMoodFilter() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
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

    @Test func hasAiAnalyzedMomentsReturnsTrueWithCategories() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "ai-cat", totalDuration: 100)
        context.insert(book)
        let m = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, categories: [.worldBuilding])
        context.insert(m)
        book.moments.append(m)
        let vm = makeViewModel(audiobook: book)
        #expect(vm.hasAiAnalyzedMoments == true)
    }

    @Test func hasAiAnalyzedMomentsReturnsTrueWithMood() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let book = Audiobook(title: "F", author: "", folderName: "ai-mood", totalDuration: 100)
        context.insert(book)
        let m = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book, mood: .inspirational)
        context.insert(m)
        book.moments.append(m)
        let vm = makeViewModel(audiobook: book)
        #expect(vm.hasAiAnalyzedMoments == true)
    }
}
