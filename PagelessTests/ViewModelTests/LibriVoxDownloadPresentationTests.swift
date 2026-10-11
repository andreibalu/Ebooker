//
//  LibriVoxDownloadPresentationTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxDownloadPresentationTests {
    @Test("Archived free book is visible only in Library during its matching restore download")
    func archivedRestoreVisibility() {
        let bookID = UUID()
        let matchingEntry = entry(phase: .failed, target: .existing(audiobookID: bookID))

        #expect(LibraryBookVisibility.includes(
            bookID: bookID,
            isDownloaded: false,
            isFreeBook: true,
            isArchived: true,
            isFavorite: true,
            tab: .allBooks,
            downloadEntry: matchingEntry
        ))
        #expect(!LibraryBookVisibility.includes(
            bookID: bookID,
            isDownloaded: false,
            isFreeBook: true,
            isArchived: true,
            isFavorite: true,
            tab: .favorites,
            downloadEntry: matchingEntry
        ))
    }

    @Test("Archived free book stays hidden without an existing-target match")
    func archivedRestoreRequiresMatchingExistingTarget() {
        let bookID = UUID()
        let wrongID = UUID()

        #expect(!LibraryBookVisibility.includes(
            bookID: bookID,
            isDownloaded: false,
            isFreeBook: true,
            isArchived: true,
            isFavorite: false,
            tab: .allBooks,
            downloadEntry: entry(phase: .downloading, target: .fresh)
        ))
        #expect(!LibraryBookVisibility.includes(
            bookID: bookID,
            isDownloaded: false,
            isFreeBook: true,
            isArchived: true,
            isFavorite: false,
            tab: .allBooks,
            downloadEntry: entry(phase: .preparing, target: .existing(audiobookID: wrongID))
        ))
    }

    private func entry(
        phase: LibriVoxDownloadManager.Phase,
        target: LibriVoxDownloadManager.Target = .fresh,
        completedTracks: Int = 2,
        totalTracks: Int = 5,
        currentTrackFraction: Double = 0
    ) -> LibriVoxDownloadManager.Entry {
        .init(
            request: .init(
                catalogID: "catalog-1",
                metadata: .init(title: "Pride and Prejudice"),
                target: target
            ),
            phase: phase,
            completedTracks: completedTracks,
            totalTracks: totalTracks,
            currentTrackFraction: currentTrackFraction,
            errorMessage: phase == .failed ? "Connection lost" : nil
        )
    }
}
