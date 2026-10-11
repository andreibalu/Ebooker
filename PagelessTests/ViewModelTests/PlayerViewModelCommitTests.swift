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
}
