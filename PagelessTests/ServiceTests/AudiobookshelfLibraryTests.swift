import Foundation
import SwiftData
import Testing
@testable import Pageless

/// ABS books in the library: token-free persistence, streaming/orphan/Cloud Library invariants,
/// and position mapping between Unpaged's (track, offset) and ABS's global `currentTime`.
@MainActor
struct AudiobookshelfLibraryTests {
    private static let base = "http://abs.example.test:13378"

    // MARK: - Adding

    @Test func urlsCarryingACredentialAreRefused() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let leaky = [URL(string: "\(Self.base)/api/items/item1/file/1?token=\(Self.secret)")!,
                     URL(string: "\(Self.base)/api/items/item1/file/2")!]
        #expect(throws: AudiobookshelfError.invalidMediaURL) {
            try AudiobookshelfLibraryService.addToLibrary(
                item: try Self.item(), trackURLs: leaky, progress: nil, coverArtData: nil, modelContext: context)
        }
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).isEmpty)
        #expect(AudiobookshelfLibraryService.containsCredential(URL(string: "https://x/y?api_key=1")!))
        #expect(!AudiobookshelfLibraryService.containsCredential(URL(string: "https://x/y?page=1")!))
    }

    @Test func addingTheSameItemTwiceReusesTheRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = try AudiobookshelfLibraryService.addToLibrary(
            item: try Self.item(), trackURLs: Self.urls(), progress: nil, coverArtData: nil, modelContext: context)
        let second = try AudiobookshelfLibraryService.addToLibrary(
            item: try Self.item(), trackURLs: Self.urls(), progress: nil, coverArtData: Data([1]), modelContext: context)
        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<Audiobook>()).count == 1)
        #expect(second.coverArtData == Data([1]))
        #expect(try AudiobookshelfLibraryService.existingBook(itemID: "item1", modelContext: context)?.id == first.id)
    }

    @Test func serverProgressSeedsTheStartingPosition() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let progress = try JSONDecoder().decode(ABSMediaProgress.self, from: Data(
            #"{"libraryItemId":"item1","duration":40,"progress":0.6,"currentTime":24.5,"isFinished":false}"#.utf8))
        let book = try AudiobookshelfLibraryService.addToLibrary(
            item: try Self.item(), trackURLs: Self.urls(), progress: progress, coverArtData: nil, modelContext: context)
        #expect(book.currentTrackIndex == 1)
        #expect(abs(book.currentTime - 4.5) < 0.001)
        #expect(book.progressTrackIndex == 1)
    }

    // MARK: - Position mapping

    @Test func positionMappingRoundTrips() {
        let durations: [Double] = [20, 30, 10]
        #expect(AudiobookshelfLibraryService.globalTime(trackIndex: 0, timeInTrack: 5, trackDurations: durations) == 5)
        #expect(AudiobookshelfLibraryService.globalTime(trackIndex: 2, timeInTrack: 4, trackDurations: durations) == 54)
        let position = AudiobookshelfLibraryService.position(forGlobalTime: 54, trackDurations: durations)
        #expect(position.trackIndex == 2 && position.timeInTrack == 4)
        let boundary = AudiobookshelfLibraryService.position(forGlobalTime: 20, trackDurations: durations)
        #expect(boundary.trackIndex == 1 && boundary.timeInTrack == 0)
        let past = AudiobookshelfLibraryService.position(forGlobalTime: 500, trackDurations: durations)
        #expect(past.trackIndex == 2 && past.timeInTrack == 10)
    }

    @Test func progressSnapshotUsesBookGlobalTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = try AudiobookshelfLibraryService.addToLibrary(
            item: try Self.item(), trackURLs: Self.urls(), progress: nil, coverArtData: nil, modelContext: context)
        let snapshot = try #require(AudiobookshelfLibraryService.progressSnapshot(
            for: book, trackIndex: 1, timeInTrack: 5, isFinished: false))
        #expect(snapshot.itemID == "item1")
        #expect(snapshot.currentTime == 25)
        #expect(snapshot.duration == 40)
        let finished = try #require(AudiobookshelfLibraryService.progressSnapshot(
            for: book, trackIndex: 0, timeInTrack: 0, isFinished: true))
        #expect(finished.currentTime == 40 && finished.isFinished)

        let own = Audiobook(title: "Own", folderName: "f")
        #expect(AudiobookshelfLibraryService.progressSnapshot(for: own, trackIndex: 0, timeInTrack: 1, isFinished: false) == nil)
    }

    // MARK: - Invariants (orphans, Cloud Library, visibility)

    @Test func absBooksAreNeverTreatedAsOrphans() {
        let abs = Audiobook(title: "ABS", folderName: "f", absItemID: "item1", isDownloaded: false)
        #expect(!OrphanDetectionService.needsLocalFileCheck(abs))
        #expect(!OrphanDetectionService.shouldMarkOrphan(abs, hasLocalFiles: false))
        #expect(!abs.isCloudOnlyOrphan)

        // Even a stray downloaded flag on an ABS row must not trigger the local-file orphan check.
        let flagged = Audiobook(title: "ABS", folderName: "f", absItemID: "item1", isDownloaded: true)
        #expect(!OrphanDetectionService.shouldMarkOrphan(flagged, hasLocalFiles: false))

        let own = Audiobook(title: "Own", folderName: "f", isDownloaded: true)
        #expect(OrphanDetectionService.shouldMarkOrphan(own, hasLocalFiles: false))
        #expect(!OrphanDetectionService.shouldMarkOrphan(own, hasLocalFiles: true))
        let ownOrphan = Audiobook(title: "Own", folderName: "f", isDownloaded: false)
        #expect(ownOrphan.isCloudOnlyOrphan)
        #expect(!ownOrphan.isStreamingOnly)
    }

    @Test func cloudLibraryPutsABSBooksUnderStreaming() {
        let abs = Audiobook(title: "ABS", folderName: "f", absItemID: "item1", isDownloaded: false)
        #expect(CloudLibraryBucket.bucket(for: abs) == .streaming)

        let free = Audiobook(title: "Free", folderName: "f", isFreeBook: true, catalogId: "1", isDownloaded: false)
        #expect(CloudLibraryBucket.bucket(for: free) == .streaming)

        let ownOrphan = Audiobook(title: "Own", folderName: "f", isDownloaded: false)
        #expect(CloudLibraryBucket.bucket(for: ownOrphan) == .iCloudOnly)

        let local = Audiobook(title: "Own", folderName: "f", isDownloaded: true)
        #expect(CloudLibraryBucket.bucket(for: local) == .onThisPhone)

        let archivedFree = Audiobook(title: "Free", folderName: "f", isFreeBook: true, catalogId: "1", isDownloaded: false)
        archivedFree.isArchived = true
        #expect(CloudLibraryBucket.bucket(for: archivedFree) == .removedFree)
    }

    // MARK: - Helpers

    /// A stand-in credential string; asserting it never lands in a stored field.
    private static let secret = "s3cr3t-tok"

    private static func item() throws -> ABSLibraryItem {
        let json = #"{"id":"item1","libraryId":"lib1","mediaType":"book","media":{"metadata":{"title":"Frankenstein","authorName":"Mary Shelley"},"duration":40,"tracks":[{"index":1,"startOffset":0,"duration":20,"title":"chapter-01.mp3","contentUrl":"/api/items/item1/file/1","mimeType":"audio/mpeg","metaTags":{"tagTitle":"Letter 1"}},{"index":2,"startOffset":20,"duration":20,"title":"chapter-02.mp3","contentUrl":"/api/items/item1/file/2","mimeType":"audio/mpeg"}]}}"#
        return try JSONDecoder().decode(ABSLibraryItem.self, from: Data(json.utf8))
    }

    private static func urls() -> [URL] {
        [URL(string: "\(base)/api/items/item1/file/1")!, URL(string: "\(base)/api/items/item1/file/2")!]
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// Chapter titles for server books with chapters that do not align with files.
@MainActor
struct ABSViewModelLogicTests {
    @Test func trackTitlesComeFromChapters() throws {
        func track(_ index: Int, _ start: Double, _ duration: Double, _ file: String, tag: String? = nil) -> ABSAudioTrack {
            ABSAudioTrack(index: index, startOffset: start, duration: duration, title: file, contentUrl: "/f/\(index)",
                          mimeType: "audio/mpeg", metaTags: tag.map { ABSAudioTrack.MetaTags(tagTitle: $0) })
        }
        let tracks = [track(1, 0, 20, "01.mp3", tag: "File 1"), track(2, 20, 20, "02.mp3", tag: "File 2")]

        // One chapter per file: chapter titles win over file tags.
        let perFile = [ABSChapter(id: 0, start: 0, end: 20, title: "Letter 1"),
                       ABSChapter(id: 1, start: 20, end: 40, title: "Chapter 1")]
        #expect(AudiobookshelfLibraryService.trackTitles(tracks: tracks, chapters: perFile) == ["Letter 1", "Chapter 1"])

        // More chapters than files: a chapter starting where a file starts names it.
        let many = [ABSChapter(id: 0, start: 0, end: 10, title: "Preface"),
                    ABSChapter(id: 1, start: 10, end: 20, title: "Letter 1"),
                    ABSChapter(id: 2, start: 20.4, end: 40, title: "Letter 2")]
        #expect(AudiobookshelfLibraryService.trackTitles(tracks: tracks, chapters: many) == ["Preface", "Letter 2"])

        // No usable chapters: tag title, else file name without extension.
        let untagged = [track(1, 0, 20, "chapter-01.mp3"), track(2, 20, 20, "chapter-02.mp3", tag: " ")]
        #expect(AudiobookshelfLibraryService.trackTitles(tracks: untagged, chapters: []) == ["chapter-01", "chapter-02"])
        #expect(AudiobookshelfLibraryService.trackTitles(tracks: tracks, chapters: [ABSChapter(id: 0, start: 5, end: 9, title: "Mid")])
                == ["File 1", "File 2"])
    }
}
