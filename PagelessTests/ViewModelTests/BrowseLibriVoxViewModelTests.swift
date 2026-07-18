import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct BrowseLibriVoxViewModelTests {
    @Test func incompleteIndexSearchesLibriVoxAndPersistsResults() async throws {
        let container = try makeContainer()
        let remote = RemoteSearchStub(results: [makeAPIBook(id: "remote-1", title: "Remote Result")])
        let viewModel = BrowseLibriVoxViewModel(
            remoteSearch: remote,
            isLocalSearchReady: { false }
        )

        await viewModel.performSearch(query: "remote", modelContext: container.mainContext)

        #expect(remote.queries == ["remote"])
        #expect(viewModel.searchResults.map(\.id) == ["remote-1"])
        #expect(viewModel.searchSource == .librivox)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LibriVoxBook>()) == 1)
    }

    @Test func completeIndexSearchesLocallyWithoutNetwork() async throws {
        let container = try makeContainer()
        container.mainContext.insert(makeBook(id: "local-1", title: "Local Treasure"))
        try container.mainContext.save()
        let remote = RemoteSearchStub(results: [makeAPIBook(id: "remote-1", title: "Remote Result")])
        let viewModel = BrowseLibriVoxViewModel(
            remoteSearch: remote,
            isLocalSearchReady: { true }
        )

        await viewModel.performSearch(query: "Treasure", modelContext: container.mainContext)

        #expect(remote.queries.isEmpty)
        #expect(viewModel.searchResults.map(\.id) == ["local-1"])
        #expect(viewModel.searchSource == .local)
    }

    @Test func incompleteOfflineSearchFallsBackToSavedMatches() async throws {
        let container = try makeContainer()
        container.mainContext.insert(makeBook(id: "saved-1", title: "Saved Treasure"))
        try container.mainContext.save()
        let remote = RemoteSearchStub(error: URLError(.notConnectedToInternet))
        let viewModel = BrowseLibriVoxViewModel(
            remoteSearch: remote,
            isLocalSearchReady: { false }
        )

        await viewModel.performSearch(query: "Treasure", modelContext: container.mainContext)

        #expect(viewModel.searchResults.map(\.id) == ["saved-1"])
        #expect(viewModel.searchSource == .savedFallback)
    }

    @Test func staleOpenedBookRefreshesRelevantMetadata() async throws {
        let container = try makeContainer()
        let book = makeBook(id: "stale-1", title: "Old Title")
        book.lastSyncedAt = Date(timeIntervalSince1970: 0)
        container.mainContext.insert(book)
        try container.mainContext.save()
        let remote = RemoteSearchStub(
            refreshedBook: makeAPIBook(id: "stale-1", title: "Fresh Title")
        )
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote)

        await viewModel.refreshBookIfStale(
            book,
            modelContext: container.mainContext,
            now: Date(timeIntervalSince1970: 100_000)
        )

        #expect(remote.fetchedIDs == ["stale-1"])
        #expect(book.title == "Fresh Title")
    }

    @Test func freshOpenedBookSkipsRemoteRefresh() async throws {
        let container = try makeContainer()
        let book = makeBook(id: "fresh-1")
        book.lastSyncedAt = Date(timeIntervalSince1970: 90_000)
        let remote = RemoteSearchStub(refreshedBook: makeAPIBook(id: "fresh-1", title: "Changed"))
        let viewModel = BrowseLibriVoxViewModel(remoteSearch: remote)

        await viewModel.refreshBookIfStale(
            book,
            modelContext: container.mainContext,
            now: Date(timeIntervalSince1970: 100_000)
        )

        #expect(remote.fetchedIDs.isEmpty)
        #expect(book.title == "Local Book")
    }

    @Test func catalogBookResolvesExactLocalID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = makeBook(id: "book-42")
        context.insert(book)
        try context.save()

        let result = BrowseLibriVoxViewModel().catalogBook(
            id: "book-42",
            modelContext: context
        )

        #expect(result === book)
    }

    @Test func catalogBookReturnsNilForMissingID() throws {
        let container = try makeContainer()

        #expect(BrowseLibriVoxViewModel().catalogBook(
            id: "missing",
            modelContext: container.mainContext
        ) == nil)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LibriVoxBook.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeBook(id: String, title: String = "Local Book") -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: title,
            authorDisplay: "Local Author",
            bookDescription: "Description",
            language: "English",
            totalTimeSecs: 3_600
        )
    }

    private func makeAPIBook(id: String, title: String) -> LibriVoxAPIBook {
        LibriVoxAPIBook(
            id: id,
            title: title,
            description: "Description",
            totalTimeSecs: 3_600,
            authors: [LibriVoxAPIAuthor(firstName: "Remote", lastName: "Author")],
            language: "English",
            urlLibrivox: nil,
            urlIarchive: nil,
            urlRss: nil,
            coverartThumbnail: nil,
            genres: []
        )
    }
}

@MainActor
private final class RemoteSearchStub: LibriVoxRemoteSearching {
    private(set) var queries: [String] = []
    private(set) var fetchedIDs: [String] = []
    private let results: [LibriVoxAPIBook]
    private let refreshedBook: LibriVoxAPIBook?
    private let error: Error?

    init(
        results: [LibriVoxAPIBook] = [],
        refreshedBook: LibriVoxAPIBook? = nil,
        error: Error? = nil
    ) {
        self.results = results
        self.refreshedBook = refreshedBook
        self.error = error
    }

    func search(query: String) async throws -> [LibriVoxAPIBook] {
        queries.append(query)
        if let error { throw error }
        return results
    }

    func fetchBook(id: String) async throws -> LibriVoxAPIBook? {
        fetchedIDs.append(id)
        if let error { throw error }
        return refreshedBook ?? results.first { $0.id == id }
    }
}
