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
