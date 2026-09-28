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

    @Test func addingStoresATokenlessStreamingBook() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = try Self.item()
        let book = try AudiobookshelfLibraryService.addToLibrary(
            item: item, trackURLs: Self.urls(), progress: nil, coverArtData: nil, modelContext: context)

        #expect(book.absItemID == "item1")
        #expect(book.isAudiobookshelfBook)
        #expect(!book.isFreeBook)
        #expect(!book.isDownloaded)
        #expect(book.isStreamingOnly)
        #expect(!book.isCloudOnlyOrphan)
        #expect(book.isInActiveLibrary)
        #expect(book.totalDuration == 40)
        #expect(book.sortedTracks.map(\.title) == ["Letter 1", "chapter-02"])

        // No credential anywhere in what gets persisted (and synced to iCloud).
        let rows = try context.fetch(FetchDescriptor<AudioTrack>())
        #expect(rows.count == 2)
        for track in rows {
            let stored = [track.remoteURLString ?? "", track.storedFileName, track.originalFileName, track.title]
            for value in stored {
                #expect(!value.localizedCaseInsensitiveContains("token"), "\(value)")
                #expect(!value.contains(Self.secret), "\(value)")
            }
            #expect(track.remoteURLString?.hasPrefix(Self.base) == true)
        }
        #expect(!book.title.contains(Self.secret))
        #expect(!book.folderName.contains(Self.secret))
    }

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

    @Test func absBooksAreVisibleInTheLibraryWithoutLocalFiles() {
        let id = UUID()
        #expect(LibraryBookVisibility.includes(bookID: id, isDownloaded: false, isFreeBook: false, isArchived: false,
                                               isFavorite: false, isAudiobookshelfBook: true, tab: .allBooks, downloadEntry: nil))
        #expect(LibraryBookVisibility.includes(bookID: id, isDownloaded: false, isFreeBook: false, isArchived: false,
                                               isFavorite: true, isAudiobookshelfBook: true, tab: .favorites, downloadEntry: nil))
        // An own-book orphan stays hidden (it belongs to Cloud Library).
        #expect(!LibraryBookVisibility.includes(bookID: id, isDownloaded: false, isFreeBook: false, isArchived: false,
                                                isFavorite: false, isAudiobookshelfBook: false, tab: .allBooks, downloadEntry: nil))
    }

    @Test func playbackErrorsReadAsPlainWords() {
        #expect(AudioPlayerManager.audiobookshelfPlaybackMessage(for: AudiobookshelfError.notConnected).contains("Connect"))
        #expect(AudioPlayerManager.audiobookshelfPlaybackMessage(for: AudiobookshelfError.offline).contains("offline"))
        #expect(AudioPlayerManager.audiobookshelfPlaybackMessage(for: AudiobookshelfError.expiredToken).contains("expired"))
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

/// Connect-sheet and browse view-model logic that doesn't need a server.
@MainActor
struct ABSViewModelLogicTests {
    @Test func connectErrorsLandUnderTheFieldTheyConcern() {
        typealias VM = ABSConnectViewModel
        #expect(VM.fieldError(for: AudiobookshelfError.unreachableServer, mode: .signIn, host: "h").field == .server)
        #expect(VM.fieldError(for: AudiobookshelfError.unreachableServer, mode: .signIn, host: "nas:13378").message.contains("nas:13378"))
        #expect(VM.fieldError(for: AudiobookshelfError.badCredentials, mode: .signIn, host: "h").field == .password)
        #expect(VM.fieldError(for: AudiobookshelfError.badCredentials, mode: .apiKey, host: "h").field == .apiKey)
        let inactive = VM.fieldError(for: AudiobookshelfError.inactiveAPIKey, mode: .apiKey, host: "h")
        #expect(inactive.field == .apiKey)
        #expect(inactive.message.contains("Settings → API Keys"))
        #expect(VM.fieldError(for: AudiobookshelfError.insecureConnection, mode: .signIn, host: "h").field == .server)
        #expect(VM.fieldError(for: AudiobookshelfError.notAudiobookshelfServer, mode: .signIn, host: "h").field == .server)
    }

    @Test func connectValidatesBeforeTouchingTheNetwork() async {
        let account = ABSAccount(credentials: MockABSCredentialStore())
        let vm = ABSConnectViewModel(serverText: "not a url")
        vm.username = "u"; vm.password = "p"
        #expect(await vm.connect(account: account, isNetworkAvailable: true) == false)
        #expect(vm.error?.field == .server)

        vm.serverText = "https://abs.example.test"
        #expect(await vm.connect(account: account, isNetworkAvailable: false) == false)
        #expect(vm.error?.field == .server)
        #expect(!account.isConnected)
    }

    @Test func browseRailsFilterAndOrder() throws {
        func item(_ id: String, _ title: String, author: String, added: Double) throws -> ABSLibraryItem {
            let json = #"{"id":"\#(id)","libraryId":"l","mediaType":"book","addedAt":\#(added),"media":{"metadata":{"title":"\#(title)","authorName":"\#(author)"}}}"#
            return try JSONDecoder().decode(ABSLibraryItem.self, from: Data(json.utf8))
        }
        func progress(_ id: String, _ time: Double, finished: Bool = false, hidden: Bool = false, updated: Double) throws -> ABSMediaProgress {
            let json = #"{"libraryItemId":"\#(id)","duration":100,"progress":\#(time / 100),"currentTime":\#(time),"isFinished":\#(finished),"hideFromContinueListening":\#(hidden),"lastUpdate":\#(updated)}"#
            return try JSONDecoder().decode(ABSMediaProgress.self, from: Data(json.utf8))
        }
        let items = [try item("a", "Dracula", author: "Bram Stoker", added: 1),
                     try item("b", "Emma", author: "Jane Austen", added: 3),
                     try item("c", "Frankenstein", author: "Mary Shelley", added: 2),
                     try item("d", "Persuasion", author: "Jane Austen", added: 4)]
        let map = ["a": try progress("a", 10, updated: 5),
                   "b": try progress("b", 50, updated: 9),
                   "c": try progress("c", 100, finished: true, updated: 10),
                   "d": try progress("d", 20, hidden: true, updated: 11)]
        #expect(ABSBrowseViewModel.continueListening(items: items, progress: map).map(\.id) == ["b", "a"])
        #expect(ABSBrowseViewModel.recentlyAdded(items: items, limit: 2).map(\.id) == ["d", "b"])
        // Hidden while All Books already shows everything.
        #expect(ABSBrowseViewModel.recentlyAdded(items: items, limit: 4).isEmpty)
        #expect(ABSBrowseViewModel.recentlyAdded(items: items).isEmpty)
        #expect(ABSBrowseViewModel.filter(items, query: "austen").map(\.id) == ["b", "d"])
        #expect(ABSBrowseViewModel.filter(items, query: "frank").map(\.id) == ["c"])
        #expect(ABSBrowseViewModel.filter(items, query: "  ").count == 4)
    }

    @Test func browseErrorsMapToOneStateEach() {
        #expect(ABSBrowseViewModel.phase(for: AudiobookshelfError.offline) == .offline)
        #expect(ABSBrowseViewModel.phase(for: AudiobookshelfError.unreachableServer) == .unreachable)
        #expect(ABSBrowseViewModel.phase(for: AudiobookshelfError.serverError(status: 503)) == .unreachable)
        #expect(ABSBrowseViewModel.phase(for: AudiobookshelfError.expiredToken) == .signedOut)
        #expect(ABSBrowseViewModel.phase(for: AudiobookshelfError.notConnected) == .signedOut)
    }

    @Test func browseWithoutAConnectionShowsSignedOut() async {
        let vm = ABSBrowseViewModel()
        await vm.load(account: ABSAccount(credentials: MockABSCredentialStore()), preferredLibraryID: nil, isNetworkAvailable: true)
        #expect(vm.phase == .signedOut)
    }

    @Test func detailEyebrowKeepsDurationLowercase() {
        #expect(ABSBookDetailView.durationText(41_520) == "11 hr 32 min")
        #expect(ABSBookDetailView.durationText(7_200) == "2 hr")
        #expect(ABSBookDetailView.durationText(2_700) == "45 min")
        #expect(ABSBookDetailView.durationText(40) == "under 1 min")
        #expect(ABSBookDetailView.eyebrowText(durationSeconds: 41_520, chapterCount: 2) == "11 hr 32 min · 2 CHAPTERS")
        #expect(ABSBookDetailView.eyebrowText(durationSeconds: 40, chapterCount: 1) == "under 1 min · 1 CHAPTER")
    }

    @Test func listenedTextPrefersTheLocalPosition() throws {
        let json = #"{"libraryItemId":"x","duration":100,"progress":0.3,"currentTime":30,"isFinished":false}"#
        let server = try JSONDecoder().decode(ABSMediaProgress.self, from: Data(json.utf8))
        #expect(ABSBookDetailViewModel.listenedText(libraryBook: nil, serverProgress: server) == "30% listened")
        #expect(ABSBookDetailViewModel.listenedText(libraryBook: nil, serverProgress: nil) == nil)

        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let book = Audiobook(title: "T", author: "A", folderName: "f", totalDuration: 100, absItemID: "x", isDownloaded: false)
        context.insert(book)
        let track = AudioTrack(title: "One", originalFileName: "one.mp3", storedFileName: "", orderIndex: 0, duration: 100)
        context.insert(track)
        track.audiobook = book
        book.tracks.append(track)
        book.currentTime = 75
        #expect(ABSBookDetailViewModel.listenedText(libraryBook: book, serverProgress: server) == "75% listened")
        book.isFinished = true
        #expect(ABSBookDetailViewModel.listenedText(libraryBook: book, serverProgress: server) == "Finished")
    }

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
