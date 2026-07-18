import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxSearchAndSyncTests {
    @Test func remoteSearchMergeDeduplicatesAndRanksTitleBeforeAuthor() {
        let title = makeBook(id: "1", title: "Treasure Island", author: "Robert Louis Stevenson")
        let author = makeBook(id: "2", title: "Kidnapped", author: "Treasure Writer")

        let results = LibriVoxAPIClient.rankAndMergeSearchResults(
            titleMatches: [title],
            authorMatches: [title, author],
            query: "treasure"
        )

        #expect(results.map(\.id) == ["1", "2"])
    }

    @Test func syncIsDueWhenIndexIncompleteOrOlderThanOneDay() {
        let now = Date(timeIntervalSince1970: 200_000)

        #expect(LibriVoxCatalogSync.syncIsDue(
            isLocalSearchReady: false,
            lastSyncDate: nil,
            now: now
        ))
        #expect(!LibriVoxCatalogSync.syncIsDue(
            isLocalSearchReady: true,
            lastSyncDate: now.addingTimeInterval(-86_399),
            now: now
        ))
        #expect(LibriVoxCatalogSync.syncIsDue(
            isLocalSearchReady: true,
            lastSyncDate: now.addingTimeInterval(-86_400),
            now: now
        ))
    }

    private func makeBook(id: String, title: String, author: String) -> LibriVoxAPIBook {
        let parts = author.split(separator: " ")
        return LibriVoxAPIBook(
            id: id,
            title: title,
            description: "",
            totalTimeSecs: 1,
            authors: [LibriVoxAPIAuthor(
                firstName: parts.first.map(String.init),
                lastName: parts.dropFirst().isEmpty ? nil : parts.dropFirst().joined(separator: " ")
            )],
            language: "English",
            urlLibrivox: nil,
            urlIarchive: nil,
            urlRss: nil,
            coverartThumbnail: nil,
            genres: []
        )
    }
}
