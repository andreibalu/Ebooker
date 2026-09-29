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
            recapProvider: MockRecapService(),
            segmentTranscriber: MockSegmentTranscriber()
        )
    }

    @Test func clearFiltersRemovesAllActiveFilters() {
        let vm = makeViewModel()
        #expect(vm.hasActiveFilters == false)

        vm.filterCategories = [.dialogue, .action]
        vm.filterCharacters = ["alice"]
        vm.filterMoods = [.tense]
        #expect(vm.hasActiveFilters == true)

        vm.clearFilters()

        #expect(vm.filterCategories.isEmpty)
        #expect(vm.filterCharacters.isEmpty)
        #expect(vm.filterMoods.isEmpty)
        #expect(vm.hasActiveFilters == false)
    }

    @Test func filteredMomentsPlacesNewestPinnedFirstThenUnpinned() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "Pin Test", author: "", folderName: "pin-order-test", totalDuration: 600)
        context.insert(book)

        let olderPinned = Moment(trackIndex: 0, time: 10, label: "Old pinned", audiobook: book)
        olderPinned.createdAt = Date(timeIntervalSince1970: 1_000)
        olderPinned.isPinned = true
        let unpinned = Moment(trackIndex: 0, time: 20, label: "Unpinned", audiobook: book)
        unpinned.createdAt = Date(timeIntervalSince1970: 2_000)
        let newerPinned = Moment(trackIndex: 0, time: 30, label: "New pinned", audiobook: book)
        newerPinned.createdAt = Date(timeIntervalSince1970: 3_000)
        newerPinned.isPinned = true

        for moment in [olderPinned, unpinned, newerPinned] {
            context.insert(moment)
            book.moments.append(moment)
        }

        let vm = makeViewModel(audiobook: book)
        #expect(vm.filteredMoments.map(\.id) == [newerPinned.id, olderPinned.id, unpinned.id])
    }

    // MARK: - Progress recap persistence

    @Test func hydratesStoredRecapOnlyWhenAnchorMatchesProgressMarker() {
        // A marker still at the 120s anchor hydrates; one that moved on to 300s does not.
        let cases: [(progressTime: Double, text: String?, headline: String?)] = [
            (120, "Summary text", "Midnight chase"),
            (300, nil, nil),
        ]
        for expected in cases {
            let book = makeAudiobook()
            book.progressTrackIndex = 0
            book.progressTime = expected.progressTime
            book.storeProgressRecap(
                text: "Summary text",
                headline: "Midnight chase",
                anchorTrackIndex: 0,
                anchorTime: 120
            )
            let vm = makeViewModel(audiobook: book)

            #expect(vm.recapText == expected.text)
            #expect(vm.recapProgressHeadline == expected.headline)
        }
    }

    @Test func reconcileStoredRecapClearsMismatchedPersistedRecap() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
            recapProvider: MockRecapService(),
            segmentTranscriber: MockSegmentTranscriber()
        )
        vm.reconcileStoredRecap(modelContext: context)

        #expect(book.progressRecapText == nil)
        #expect(vm.recapText == nil)
    }

    @Test func reconcileStoredRecapClearsStaleError() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "T", author: "", folderName: "reconcile-error-test", totalDuration: 600)
        context.insert(book)

        let vm = makeViewModel(audiobook: book)
        vm.recapError = "Could not transcribe audio."
        vm.reconcileStoredRecap(modelContext: context)

        #expect(vm.recapError == nil)
    }

    @Test func loadRecapOnUndownloadedBookExplainsMissingAudio() async throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(
            title: "Streamed",
            author: "",
            folderName: "streaming-recap-test",
            totalDuration: 600,
            isDownloaded: false
        )
        let track = AudioTrack(
            title: "Ch1",
            originalFileName: "s.m4a",
            storedFileName: "s.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks.append(track)
        context.insert(book)

        let vm = makeViewModel(audiobook: book)
        await vm.loadRecap(trackIndex: 0, progressTime: 300, includeProgressHeadline: false, modelContext: context)

        #expect(vm.recapError == "Audio for this book isn't on this iPhone.")
        #expect(vm.recapText == nil)
    }

    @Test func loadRecapStoresRecapOnAudiobook() async throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
            recapProvider: recap,
            segmentTranscriber: MockSegmentTranscriber()
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
            recapProvider: MockRecapService(),
            segmentTranscriber: MockSegmentTranscriber()
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

    @Test func loadRecapPrimaryPathSkipsAuthorization() async throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "T3", author: "", folderName: "primary-path-test", totalDuration: 600)
        let track = AudioTrack(
            title: "Ch1",
            originalFileName: "c.m4a",
            storedFileName: "c.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks.append(track)
        context.insert(book)

        let transcription = MockTranscriptionService()
        let segment = MockSegmentTranscriber()
        let vm = AudiobookDetailViewModel(
            audiobook: book,
            transcription: transcription,
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService(),
            segmentTranscriber: segment
        )
        await vm.loadRecap(trackIndex: 0, progressTime: 300, includeProgressHeadline: false, modelContext: context)

        #expect(vm.recapText == "Mock recap of recent events.")
        #expect(segment.callCount == 1)
        #expect(segment.lastRange?.start == 100)  // 300 − 200
        #expect(segment.lastRange?.end == 300)
        #expect(transcription.authorizationRequestCount == 0)
    }

    @Test func loadRecapFallsBackToLegacyWhenPrimaryThrows() async throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let book = Audiobook(title: "T4", author: "", folderName: "fallback-path-test", totalDuration: 600)
        let track = AudioTrack(
            title: "Ch1",
            originalFileName: "d.m4a",
            storedFileName: "d.m4a",
            orderIndex: 0,
            duration: 600,
            audiobook: book
        )
        book.tracks.append(track)
        context.insert(book)

        let transcription = MockTranscriptionService()
        let segment = MockSegmentTranscriber()
        segment.shouldThrow = true
        let vm = AudiobookDetailViewModel(
            audiobook: book,
            transcription: transcription,
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService(),
            segmentTranscriber: segment
        )
        await vm.loadRecap(trackIndex: 0, progressTime: 300, includeProgressHeadline: false, modelContext: context)

        #expect(vm.recapText == "Mock recap of recent events.")
        #expect(transcription.authorizationRequestCount == 1)
        #expect(transcription.transcribeCallCount == 1)
    }

    @Test func obtainTranscriptPropagatesCancellationWithoutLegacyFallback() async throws {
        let transcription = MockTranscriptionService()
        let segment = BlockingSegmentTranscriber()
        let vm = AudiobookDetailViewModel(
            audiobook: makeAudiobook(),
            transcription: transcription,
            audioExtractor: MockAudioExtractor(),
            recapProvider: MockRecapService(),
            segmentTranscriber: segment
        )

        let task = Task { @MainActor in
            try await vm.obtainTranscript(
                fileURL: URL(fileURLWithPath: "/tmp/a.mp3"), startSeconds: 10, endSeconds: 30
            )
        }
        await segment.waitUntilStarted()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancellation should propagate from the primary path")
        } catch is CancellationError {
            // Expected: cancellation must not be interpreted as a primary failure.
        } catch {
            Issue.record("Unexpected error after cancellation: \(error)")
        }

        #expect(transcription.authorizationRequestCount == 0)
        #expect(transcription.transcribeCallCount == 0)
    }

    @Test func produceRecapSurfacesUnsafeContentCopy() async {
        let recap = MockRecapService()
        recap.errorToThrow = RecapError.unsafeContent
        let vm = AudiobookDetailViewModel(
            audiobook: makeAudiobook(),
            transcription: MockTranscriptionService(),
            audioExtractor: MockAudioExtractor(),
            recapProvider: recap,
            segmentTranscriber: MockSegmentTranscriber()
        )

        await vm.produceRecap(
            transcript: "t", includeProgressHeadline: false,
            anchorTrackIndex: 0, anchorTime: 1, modelContext: nil, onSuccessfulRecap: nil
        )

        #expect(vm.recapError == "Apple Intelligence declined to summarize this passage.")
        #expect(vm.recapText == nil)
    }
}
