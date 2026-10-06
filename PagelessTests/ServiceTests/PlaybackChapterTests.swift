//
//  PlaybackChapterTests.swift
//  PagelessTests
//

import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Pageless

private final class FixtureBundleToken {}

// MARK: - Embedded chapter reading

@MainActor
struct EmbeddedChapterReaderTests {

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return try #require(bundle.url(forResource: base, withExtension: ext))
    }

    /// The fixtures tag their chapters with the "und" language, as most audiobook encoders do.
    /// `bestMatchingPreferredLanguages` alone returns nothing for them.
    @Test(arguments: ["chaptered.m4b", "chaptered.mp3"])
    func readsUndeterminedLanguageChapters(fixture: String) async throws {
        let asset = AVURLAsset(url: try fixtureURL(fixture))

        let markers = await EmbeddedChapterReader.markers(from: asset)

        #expect(markers.map(\.title) == ["Opening", "The Middle", "Ending"])
        #expect(markers.map { ($0.start * 10).rounded() / 10 } == [0, 4, 9])
    }

    @Test func fileWithoutChaptersYieldsNoMarkers() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let markers = await EmbeddedChapterReader.markers(from: AVURLAsset(url: url))

        #expect(markers.isEmpty)
    }
}

// MARK: - Chapter list construction

struct PlaybackChapterListTests {

    @Test func singleFileWithMarkersExpandsIntoChapters() {
        let chapters = PlaybackChapterList.build(
            trackTitles: ["Book"],
            trackDurations: [12],
            markersByTrack: [0: [
                ChapterMarker(title: "Opening", start: 0, end: 4),
                ChapterMarker(title: "The Middle", start: 4, end: 9),
                ChapterMarker(title: "Ending", start: 9, end: 12)
            ]]
        )

        #expect(chapters.map(\.title) == ["Opening", "The Middle", "Ending"])
        #expect(chapters.map(\.trackIndex) == [0, 0, 0])
        #expect(chapters.map(\.start) == [0, 4, 9])
        #expect(chapters.map(\.duration) == [4, 5, 3])
        #expect(chapters.map(\.index) == [0, 1, 2])
    }

    @Test func tracksWithoutMarkersStayOneChapterEach() {
        let chapters = PlaybackChapterList.build(
            trackTitles: ["Chapter 1", "Chapter 2"],
            trackDurations: [60, 90],
            markersByTrack: [1: [ChapterMarker(title: "Only one", start: 0, end: 90)]]
        )

        #expect(chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(chapters.map(\.trackIndex) == [0, 1])
        #expect(chapters.map(\.duration) == [60, 90])
    }

    @Test func sanitizingOrdersDedupesAndDropsMarkersPastTheEnd() {
        let markers = PlaybackChapterList.sanitized([
            ChapterMarker(title: " Two ", start: 30, end: 60),
            ChapterMarker(title: "One", start: 0.4, end: 30),
            ChapterMarker(title: "Two again", start: 30.2, end: 60),
            ChapterMarker(title: "Beyond", start: 500, end: 600),
            ChapterMarker(title: "Broken", start: .nan, end: 1)
        ], trackDuration: 100)

        #expect(markers == [
            ChapterMarker(title: "One", start: 0, end: 30),
            ChapterMarker(title: "Two", start: 30, end: 100)
        ])
    }

    @Test func untitledMarkersGetNumberedTitles() {
        let chapters = PlaybackChapterList.build(
            trackTitles: ["Book"],
            trackDurations: [20],
            markersByTrack: [0: [ChapterMarker(title: "", start: 0, end: 10), ChapterMarker(title: "  ", start: 10, end: 20)]]
        )

        #expect(chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
    }

    @Test func lookupFindsTheChapterContainingAPosition() {
        let chapters = PlaybackChapterList.build(
            trackTitles: ["Book", "Epilogue"],
            trackDurations: [12, 30],
            markersByTrack: [0: [
                ChapterMarker(title: "A", start: 0, end: 4),
                ChapterMarker(title: "B", start: 4, end: 9),
                ChapterMarker(title: "C", start: 9, end: 12)
            ]]
        )

        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 0, time: 0) == 0)
        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 0, time: 3.7) == 0)
        // A seek that lands a hair before a chapter start still counts as that chapter.
        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 0, time: 3.9) == 1)
        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 0, time: 10) == 2)
        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 1, time: 5) == 3)
        #expect(PlaybackChapterList.chapterIndex(in: [], trackIndex: 0, time: 0) == nil)
    }
}

// MARK: - Audiobookshelf chapter mapping

struct AudiobookshelfChapterMappingTests {

    @Test func singleFileBookGetsServerChaptersAsTimeRanges() {
        let chapters = AudiobookshelfLibraryService.playbackChapters(
            from: [
                ABSChapter(id: 0, start: 0, end: 600, title: "Letter 1"),
                ABSChapter(id: 1, start: 600, end: 1500, title: "Letter 2"),
                ABSChapter(id: 2, start: 1500, end: 3000, title: "Chapter 1")
            ],
            trackDurations: [3000]
        )

        #expect(chapters.map(\.title) == ["Letter 1", "Letter 2", "Chapter 1"])
        #expect(chapters.map(\.trackIndex) == [0, 0, 0])
        #expect(chapters.map(\.start) == [0, 600, 1500])
        #expect(chapters.map(\.duration) == [600, 900, 1500])
    }

    @Test func chaptersAcrossFilesMapToTrackAndOffset() {
        // Two 1000s files; the second chapter starts mid-file-1 and runs into file 2.
        let chapters = AudiobookshelfLibraryService.playbackChapters(
            from: [
                ABSChapter(id: 0, start: 0, end: 700, title: "One"),
                ABSChapter(id: 1, start: 700, end: 1300, title: "Two"),
                ABSChapter(id: 2, start: 1300, end: 2000, title: "Three")
            ],
            trackDurations: [1000, 1000]
        )

        #expect(chapters.map(\.trackIndex) == [0, 0, 1])
        #expect(chapters.map(\.start) == [0, 700, 300])
        #expect(chapters.map(\.duration) == [700, 600, 700])
        // Early in file 2 is still inside chapter "Two", which began in file 1.
        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 1, time: 100) == 1)
        #expect(PlaybackChapterList.chapterIndex(in: chapters, trackIndex: 1, time: 400) == 2)
    }

    @Test func chapterStartingJustBeforeAFileBoundarySnapsToTheNextFile() {
        let chapters = AudiobookshelfLibraryService.playbackChapters(
            from: [
                ABSChapter(id: 0, start: 0, end: 999.8, title: "One"),
                ABSChapter(id: 1, start: 999.8, end: 2000, title: "Two")
            ],
            trackDurations: [1000, 1000]
        )

        #expect(chapters[1].trackIndex == 1)
        #expect(chapters[1].start == 0)
    }

    @Test func fewerThanTwoChaptersFallsBackToFiles() {
        #expect(AudiobookshelfLibraryService.playbackChapters(
            from: [ABSChapter(id: 0, start: 0, end: 100, title: "Whole")],
            trackDurations: [100]
        ).isEmpty)
        #expect(AudiobookshelfLibraryService.playbackChapters(from: [], trackDurations: [100]).isEmpty)
    }
}

// MARK: - Player chapter navigation

@MainActor
@Suite(.serialized)
struct AudioPlayerChapterNavigationTests {

    private static let fixtureMarkers = [
        ChapterMarker(title: "Opening", start: 0, end: 20),
        ChapterMarker(title: "The Middle", start: 20, end: 40),
        ChapterMarker(title: "Ending", start: 40, end: 60)
    ]

    @Test func singleFileBookWithEmbeddedChaptersHasChapterNavigation() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 0)
        #expect(player.chapters.count == 1)
        #expect(player.canGoToNextChapter == false)

        player.seedUnitTestChapterMarkers(Self.fixtureMarkers, for: book.sortedTracks[0])

        #expect(player.chapters.map(\.title) == ["Opening", "The Middle", "Ending"])
        #expect(player.currentChapterIndex == 0)
        #expect(player.canGoToNextChapter)
        #expect(player.canGoToPreviousChapter == false)

        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 25)
        #expect(player.currentChapter?.title == "The Middle")
        #expect(player.canGoToPreviousChapter)

        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 45)
        #expect(player.currentChapterIndex == 2)
        #expect(player.canGoToNextChapter == false)
    }

    @Test func seekReflectsTargetImmediatelyAndIgnoresStaleTimeCallbacks() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 5)
        player.seedUnitTestChapterMarkers(Self.fixtureMarkers, for: book.sortedTracks[0])

        player.seek(to: 40)
        #expect(player.currentTime == 40)
        #expect(player.currentChapter?.title == "Ending")

        // AVPlayer still reports the pre-seek position until the seek lands.
        player.applyObservedTime(5)
        #expect(player.currentTime == 40)
        #expect(player.currentChapter?.title == "Ending")

        // Once the reported time reaches the target, normal tracking resumes.
        player.applyObservedTime(41)
        #expect(player.currentTime == 41)
        player.applyObservedTime(42)
        #expect(player.currentTime == 42)
    }

    @Test func staleSeekNeverFreezesTime() {
        let player = AudioPlayerManager()
        let book = makeBook(trackCount: 1)
        player.seedUnitTestPlaybackState(audiobook: book, track: book.sortedTracks[0], trackIndex: 0, currentTime: 5)

        player.seek(to: 40)
        player.applyObservedTime(6, now: Date().addingTimeInterval(30))

        #expect(player.currentTime == 6)
    }

    @Test func pausingWhileTheResumeSeekIsBufferingKeepsTheTarget() async {
        let player = AudioPlayerManager(loadPreparation: preparation())
        let book = makeBook(trackCount: 1)
        await player.playTrack(at: 0, in: book, time: 30)

        player.pause()
        // The stream hasn't reached the target yet and still reports 0.
        player.applyObservedTime(0)

        #expect(player.currentTime == 30)
        #expect(book.currentTime == 30)
    }

    @Test func pauseDuringAnUncommittedChapterLoadDropsThePendingTarget() async {
        let player = AudioPlayerManager(loadPreparation: preparation())
        let book = makeBook(trackCount: 2)
        await player.playTrack(at: 0, in: book, time: 0, autoplay: false)

        player.nextChapter()
        #expect(player.pendingPlaybackTarget?.trackIndex == 1)
        player.pause()

        #expect(player.pendingPlaybackTarget == nil)
        #expect(player.canGoToNextChapter)
        // Let the queued chapter task actually run: pause must also prevent it from
        // restarting playback after the synchronous state above has been cleared.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(player.currentTrackIndex == 0)
        #expect(player.pendingPlaybackTarget == nil)
        #expect(!player.isPlaying)
    }

    @Test func rapidNextChapterTapsWithinOneFileAdvanceOncePerTap() async {
        let player = AudioPlayerManager(loadPreparation: preparation())
        let book = makeBook(trackCount: 1)
        await player.playTrack(at: 0, in: book, time: 2, autoplay: false)
        player.seedUnitTestChapterMarkers(Self.fixtureMarkers, for: book.sortedTracks[0])
        #expect(player.currentChapterIndex == 0)

        player.nextChapter()
        player.nextChapter()

        #expect(player.currentTime == 40)
        #expect(player.currentChapter?.title == "Ending")
    }

    @Test func previousChapterRestartsThenStepsBack() async {
        let player = AudioPlayerManager(loadPreparation: preparation())
        let book = makeBook(trackCount: 1)
        await player.playTrack(at: 0, in: book, time: 30, autoplay: false)
        player.seedUnitTestChapterMarkers(Self.fixtureMarkers, for: book.sortedTracks[0])

        player.previousChapter()
        #expect(player.currentTime == 20)

        player.previousChapter()
        #expect(player.currentTime == 0)
        #expect(player.currentChapterIndex == 0)
    }

    @Test func rapidNextTrackTapsAdvanceOncePerTap() async {
        let player = AudioPlayerManager(loadPreparation: preparation())
        let book = makeBook(trackCount: 3)
        await player.playTrack(at: 0, in: book, time: 0, autoplay: false)

        // Both taps land before the first load commits.
        player.nextChapter()
        player.nextChapter()
        await waitUntil { player.pendingPlaybackTarget == nil && player.currentTrackIndex == 2 }

        #expect(player.currentTrackIndex == 2)
        #expect(book.currentTrackIndex == 2)
    }

    @Test func chapterTapInAnotherFileLoadsThatFileAtTheChapterStart() async {
        let player = AudioPlayerManager(loadPreparation: preparation())
        let book = makeBook(trackCount: 2)
        await player.playTrack(at: 0, in: book, time: 0, autoplay: false)
        player.seedUnitTestChapterMarkers(Self.fixtureMarkers, for: book.sortedTracks[1])
        #expect(player.chapters.count == 4)

        player.playChapter(player.chapters[3])
        await waitUntil { player.currentTrackIndex == 1 && player.pendingPlaybackTarget == nil }

        #expect(player.currentTrackIndex == 1)
        #expect(player.currentTime == 40)
        #expect(player.currentChapter?.title == "Ending")
    }

    @Test func loadReadsEmbeddedChaptersForTheCommittedTrack() async {
        var probed: [String] = []
        var prep = preparation()
        prep.loadChapterMarkers = { asset in
            probed.append((asset as? AVURLAsset)?.url.lastPathComponent ?? "")
            return Self.fixtureMarkers
        }
        let player = AudioPlayerManager(loadPreparation: prep)
        let book = makeBook(trackCount: 1)

        await player.playTrack(at: 0, in: book, time: 0, autoplay: false)
        await waitUntil { player.chapters.count == 3 }

        #expect(player.chapters.map(\.title) == ["Opening", "The Middle", "Ending"])
        #expect(probed == ["t0.m4b"])

        // Cached for the session: reloading the same file doesn't read it again.
        await player.playTrack(at: 0, in: book, time: 10, autoplay: false)
        await waitUntil { player.currentTime == 10 }
        #expect(probed.count == 1)
        #expect(player.chapters.count == 3)
    }

    @Test func audiobookshelfBookUsesServerChapters() async {
        var prep = preparation()
        prep.loadAudiobookshelfChapters = { itemID in
            #expect(itemID == "item-1")
            return [
                ABSChapter(id: 0, start: 0, end: 30, title: "Part One"),
                ABSChapter(id: 1, start: 30, end: 60, title: "Part Two")
            ]
        }
        let player = AudioPlayerManager(loadPreparation: prep)
        let book = makeBook(trackCount: 1, absItemID: "item-1")

        await player.playTrack(at: 0, in: book, time: 0, autoplay: false)
        await waitUntil { player.chapters.count == 2 }

        #expect(player.chapters.map(\.title) == ["Part One", "Part Two"])
        #expect(player.chapters.map(\.start) == [0, 30])
    }

    // MARK: Helpers

    private func preparation() -> AudioPlayerLoadPreparation {
        AudioPlayerLoadPreparation(
            isNetworkAvailable: { true },
            makeAudioMix: { _ in nil },
            loadDuration: { _ in CMTime(seconds: 60, preferredTimescale: 600) },
            prepareSeek: { _, _ in true }
        )
    }

    private func makeBook(trackCount: Int, absItemID: String? = nil) -> Audiobook {
        let tracks = (0..<trackCount).map { index in
            let track = AudioTrack(
                title: "Track \(index + 1)",
                originalFileName: "t\(index).m4b",
                storedFileName: "t\(index).m4b",
                orderIndex: index,
                duration: 60
            )
            track.remoteURLString = "https://example.com/t\(index).m4b"
            return track
        }
        return Audiobook(
            title: "Chaptered",
            folderName: "chaptered",
            totalDuration: 60 * Double(trackCount),
            absItemID: absItemID,
            isDownloaded: false,
            tracks: tracks
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

// MARK: - Track order

@MainActor
struct SortedTracksOrderTests {

    @Test func duplicateOrderIndexesSortTheSameWayEveryTime() throws {
        let container = try ModelContainer(
            for: Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let book = Audiobook(title: "Merged", folderName: "merged")
        context.insert(book)
        for name in ["c.m4a", "a.m4a", "b.m4a"] {
            let track = AudioTrack(title: name, originalFileName: name, storedFileName: name, orderIndex: 0, duration: 10)
            track.audiobook = book
            context.insert(track)
            book.tracks.append(track)
        }
        try context.save()

        #expect(book.sortedTracks.map(\.originalFileName) == ["a.m4a", "b.m4a", "c.m4a"])
        book.tracks.reverse()
        #expect(book.sortedTracks.map(\.originalFileName) == ["a.m4a", "b.m4a", "c.m4a"])
    }
}
