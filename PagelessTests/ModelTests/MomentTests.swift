//
//  MomentTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct MomentTests {
    private func makeBook(in context: ModelContext) -> Audiobook {
        let book = Audiobook(title: "Moment Book", author: "A", folderName: "moment-tests", totalDuration: 600)
        context.insert(book)
        return book
    }

    @Test func defaultCategoriesIsEmpty() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        context.insert(moment)
        #expect(moment.categories.isEmpty)
    }

    @Test func categoriesRoundTripsThroughJSONStorage() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        moment.categories = [.dialogue, .tension]
        context.insert(moment)
        try context.save()
        #expect(moment.categories == [.dialogue, .tension])
    }

    @Test func categoriesWithMultipleValues() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        moment.categories = [.quote, .humor, .romance, .action]
        context.insert(moment)
        #expect(Set(moment.categories) == Set([.quote, .humor, .romance, .action]))
    }

    @Test func defaultCharactersIsEmpty() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        context.insert(moment)
        #expect(moment.characters.isEmpty)
    }

    @Test func charactersRoundTripsThroughJSONStorage() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        moment.characters = ["Eve", "Wallace"]
        context.insert(moment)
        try context.save()
        #expect(moment.characters == ["Eve", "Wallace"])
    }

    @Test func defaultMoodIsNil() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        context.insert(moment)
        #expect(moment.mood == nil)
    }

    @Test func moodRoundTripsThroughRawValue() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book, mood: .mysterious)
        context.insert(moment)
        try context.save()
        #expect(moment.mood == .mysterious)
    }

    @Test func quoteLineRoundTrips() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book, quoteLine: "She opened the door.")
        context.insert(moment)
        try context.save()
        #expect(moment.quoteLine == "She opened the door.")
    }

    @Test func aiGeneratedNameDefaultsFalse() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        context.insert(moment)
        #expect(moment.aiGeneratedName == false)
    }

    @Test func notesDefaultsNil() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        context.insert(moment)
        #expect(moment.notes == nil)
    }

    @Test func isPinnedDefaultsFalse() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(trackIndex: 0, time: 1, label: "L", audiobook: book)
        context.insert(moment)
        #expect(moment.isPinned == false)
    }

    @Test func initSetsAllFieldsCorrectly() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = makeBook(in: context)
        let moment = Moment(
            trackIndex: 3,
            time: 42.5,
            label: "Full",
            audiobook: book,
            transcript: "t",
            aiGeneratedName: true,
            notes: "n",
            categories: [.reflection],
            quoteLine: "q",
            characters: ["Zed"],
            mood: .peaceful,
            isPinned: true
        )
        context.insert(moment)
        #expect(moment.trackIndex == 3)
        #expect(moment.time == 42.5)
        #expect(moment.label == "Full")
        #expect(moment.audiobook?.id == book.id)
        #expect(moment.transcript == "t")
        #expect(moment.aiGeneratedName == true)
        #expect(moment.notes == "n")
        #expect(moment.categories == [.reflection])
        #expect(moment.quoteLine == "q")
        #expect(moment.characters == ["Zed"])
        #expect(moment.mood == .peaceful)
        #expect(moment.isPinned == true)
    }
}
