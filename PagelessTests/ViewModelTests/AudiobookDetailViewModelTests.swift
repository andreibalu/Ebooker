//
//  AudiobookDetailViewModelTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

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
        #expect(vm.recapProgressHeadline == nil)
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

    @Test func filteredMomentsPlacesPinnedBeforeUnpinnedPreservingCreatedAtOrder() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "Pin Test", author: "", folderName: "pin-order-test", totalDuration: 600)
        context.insert(book)

        let older = Moment(trackIndex: 0, time: 10, label: "Old", audiobook: book)
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = Moment(trackIndex: 0, time: 20, label: "New", audiobook: book)
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        older.isPinned = true

        context.insert(older)
        context.insert(newer)
        book.moments.append(older)
        book.moments.append(newer)

        let vm = makeViewModel(audiobook: book)
        let ordered = vm.filteredMoments

        #expect(ordered.count == 2)
        #expect(ordered[0].id == older.id)
        #expect(ordered[1].id == newer.id)
    }

    @Test func filteredMomentsSortsPinnedByCreatedAtDescending() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "Pin Sort", author: "", folderName: "pin-sort-test", totalDuration: 600)
        context.insert(book)

        let a = Moment(trackIndex: 0, time: 1, label: "A", audiobook: book)
        a.createdAt = Date(timeIntervalSince1970: 1_000)
        a.isPinned = true
        let b = Moment(trackIndex: 0, time: 2, label: "B", audiobook: book)
        b.createdAt = Date(timeIntervalSince1970: 3_000)
        b.isPinned = true

        context.insert(a)
        context.insert(b)
        book.moments.append(a)
        book.moments.append(b)

        let vm = makeViewModel(audiobook: book)
        let ordered = vm.filteredMoments

        #expect(ordered.map(\.id) == [b.id, a.id])
    }

    // MARK: - Progress recap persistence

    @Test func hydratesStoredRecapWhenAnchorMatchesProgressMarker() {
        let book = makeAudiobook()
        book.progressTrackIndex = 0
        book.progressTime = 120
        book.storeProgressRecap(
            text: "Summary text",
            headline: "Midnight chase",
            anchorTrackIndex: 0,
            anchorTime: 120
        )
        let vm = makeViewModel(audiobook: book)

        #expect(vm.recapText == "Summary text")
        #expect(vm.recapProgressHeadline == "Midnight chase")
    }

    @Test func doesNotHydrateStoredRecapWhenProgressMarkerMoved() {
        let book = makeAudiobook()
        book.progressTrackIndex = 0
        book.progressTime = 300
        book.storeProgressRecap(
            text: "Stale",
            headline: "Stale H",
            anchorTrackIndex: 0,
            anchorTime: 120
        )
        let vm = makeViewModel(audiobook: book)

        #expect(vm.recapText == nil)
        #expect(vm.recapProgressHeadline == nil)
    }

    @Test func reconcileStoredRecapClearsMismatchedPersistedRecap() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "T", author: "", folderName: "reconcile-test", totalDuration: 600)
        context.insert(book)
        book.progressTrackIndex = 0
        book.progressTime = 200
        book.storeProgressRecap(text: "stale", headline: "old", anchorTrackIndex: 0, anchorTime: 100)

        let vm = AudiobookDetailViewModel(
            audiobook: book,
            transcription: MockTranscriptionService(),
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService()
        )
        vm.reconcileStoredRecap(modelContext: context)

        #expect(book.progressRecapText == nil)
        #expect(vm.recapText == nil)
    }

    @Test func loadRecapStoresRecapOnAudiobook() async throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "T", author: "", folderName: "loadrecap-test", totalDuration: 600)
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

        let recap = MockRecapService()
        recap.recapToReturn = "Generated body"
        recap.progressHeadlineToReturn = "Short title line"

        let vm = AudiobookDetailViewModel(
            audiobook: book,
            transcription: MockTranscriptionService(),
            audioExtractor: MockAudioExtractor(),
            recapProvider: recap
        )
        await vm.loadRecap(
            trackIndex: 0,
            progressTime: 300,
            includeProgressHeadline: true,
            modelContext: context
        )

        #expect(book.progressRecapText == "Generated body")
        #expect(book.progressRecapHeadline == "Short title line")
        #expect(book.progressRecapAnchorTrackIndex == 0)
        #expect(book.progressRecapAnchorTime == 300)
        #expect(vm.recapText == "Generated body")
    }

    @Test func loadRecapWithoutHeadlineStoresNilHeadlineOnAudiobook() async throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "T2", author: "", folderName: "loadrecap-test-2", totalDuration: 600)
        let track = AudioTrack(
            title: "Ch1",
            originalFileName: "b.m4a",
            storedFileName: "b.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks.append(track)
        context.insert(book)

        let vm = AudiobookDetailViewModel(
            audiobook: book,
            transcription: MockTranscriptionService(),
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService()
        )
        await vm.loadRecap(
            trackIndex: 0,
            progressTime: 300,
            includeProgressHeadline: false,
            modelContext: context
        )

        #expect(book.progressRecapText != nil)
        #expect(book.progressRecapHeadline == nil)
        #expect(vm.recapProgressHeadline == nil)
    }
}

