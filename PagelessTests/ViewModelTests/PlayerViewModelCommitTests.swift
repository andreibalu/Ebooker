//
//  PlayerViewModelCommitTests.swift
//  PagelessTests
//

import SwiftData
import Testing
@testable import Pageless

@MainActor
struct PlayerViewModelCommitTests {
    private func makeContextAndBook() throws -> (ModelContext, Audiobook, AudioTrack) {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let book = Audiobook(title: "Commit Book", author: "", folderName: "commit-vm", totalDuration: 1_000)
        let track = AudioTrack(
            title: "Ch1",
            originalFileName: "a.m4a",
            storedFileName: "a.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks.append(track)
        context.insert(book)
        return (context, book, track)
    }

    private func momentCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<Moment>()).count
    }

    @Test func commitMomentInsertsOneRowIntoContext() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 12.5
        vm.momentNameInput = "Named"
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 99)

        #expect(try momentCount(in: context) == 0)
        vm.commitMoment(player: player, modelContext: context)
        #expect(try momentCount(in: context) == 1)
    }

    @Test func commitMomentUsesLabelFromInput() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 1
        vm.momentNameInput = "Chapter Beat"
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.first?.label == "Chapter Beat")
    }

    @Test func commitMomentFallsBackToSavedMomentWhenNameEmpty() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 1
        vm.momentNameInput = "   "
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.first?.label == "Saved Moment")
    }

    @Test func commitMomentTrimsWhitespaceFromName() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 1
        vm.momentNameInput = "  trimmed  "
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.first?.label == "trimmed")
    }

    @Test func commitMomentSetsNilNoteWhenInputEmpty() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 1
        vm.momentNameInput = "N"
        vm.momentNoteInput = "  \t  "
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.first?.notes == nil)
    }

    @Test func commitMomentPreservesNoteWhenProvided() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 1
        vm.momentNameInput = "N"
        vm.momentNoteInput = "  A real note "
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.first?.notes == "A real note")
    }

    @Test func commitMomentClearsPendingMomentTime() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 5
        vm.momentNameInput = "N"
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        #expect(vm.pendingMomentTime == nil)
    }

    @Test func commitMomentTransfersAiFieldsToMoment() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.pendingMomentTime = 3
        vm.momentNameInput = "AI"
        vm.pendingMomentTranscript = "transcript body"
        vm.pendingMomentAiGenerated = true
        vm.pendingCategories = [.humor, .quote]
        vm.pendingQuoteLine = "They laughed."
        vm.pendingCharacters = ["Sam"]
        vm.pendingMood = .funny
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        let m = try #require(moments.first)
        #expect(m.transcript == "transcript body")
        #expect(m.aiGeneratedName == true)
        #expect(Set(m.categories) == Set([.humor, .quote]))
        #expect(m.quoteLine == "They laughed.")
        #expect(m.characters == ["Sam"])
        #expect(m.mood == .funny)
    }

    @Test func commitMomentDoesNothingWithoutPendingTime() throws {
        let (context, book, track) = try makeContextAndBook()
        let vm = PlayerViewModel()
        vm.momentNameInput = "Orphan"
        let player = AudioPlayerManager()
        player.seedUnitTestPlaybackState(audiobook: book, track: track, trackIndex: 0, currentTime: 0)
        vm.commitMoment(player: player, modelContext: context)
        #expect(try momentCount(in: context) == 0)
    }
}
