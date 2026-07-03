//
//  LibriVoxDownloadPresentationTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxDownloadPresentationTests {
    @Test(
        "Maps every manager phase to its visible state",
        arguments: [
            PhaseExpectation(.preparing, "Preparing…", true, true, false, false),
            PhaseExpectation(.downloading, "2 of 5 tracks", false, true, false, false),
            PhaseExpectation(.cancelling, "Cancelling…", true, false, false, false),
            PhaseExpectation(.failed, "Connection lost", false, false, true, true),
            PhaseExpectation(.complete, "Downloaded", false, false, false, false)
        ]
    )
    func mapsPhase(expectation: PhaseExpectation) {
        let presentation = LibriVoxDownloadPresentation(entry: entry(phase: expectation.phase))

        #expect(presentation.statusText == expectation.statusText)
        #expect(presentation.showsSpinner == expectation.showsSpinner)
        #expect(presentation.canCancel == expectation.canCancel)
        #expect(presentation.canRetry == expectation.canRetry)
        #expect(presentation.canDismiss == expectation.canDismiss)
    }

    @Test("Downloading maps track progress to a bounded fraction")
    func mapsProgress() {
        let presentation = LibriVoxDownloadPresentation(
            entry: entry(phase: .downloading, currentTrackFraction: 0.5)
        )

        #expect(presentation.progress == 0.5)
    }

    @Test("Manager status takes precedence over Stream on a library card")
    func managerStatusOverridesStreaming() {
        let active = entry(phase: .downloading)

        #expect(LibriVoxDownloadPresentation.cardStatus(entry: active, isStreamingOnly: true) == "Downloading 2 of 5")
        #expect(LibriVoxDownloadPresentation.cardStatus(entry: nil, isStreamingOnly: true) == "Stream")
        #expect(LibriVoxDownloadPresentation.cardStatus(entry: nil, isStreamingOnly: false) == nil)
    }

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
        currentTrackFraction: Double = 0
    ) -> LibriVoxDownloadManager.Entry {
        .init(
            request: .init(
                catalogID: "catalog-1",
                metadata: .init(title: "Pride and Prejudice"),
                target: target
            ),
            phase: phase,
            completedTracks: 2,
            totalTracks: 5,
            currentTrackFraction: currentTrackFraction,
            errorMessage: phase == .failed ? "Connection lost" : nil
        )
    }
}

struct PhaseExpectation: Sendable, CustomTestStringConvertible {
    let phase: LibriVoxDownloadManager.Phase
    let statusText: String
    let showsSpinner: Bool
    let canCancel: Bool
    let canRetry: Bool
    let canDismiss: Bool

    var testDescription: String { String(describing: phase) }

    init(
        _ phase: LibriVoxDownloadManager.Phase,
        _ statusText: String,
        _ showsSpinner: Bool,
        _ canCancel: Bool,
        _ canRetry: Bool,
        _ canDismiss: Bool
    ) {
        self.phase = phase
        self.statusText = statusText
        self.showsSpinner = showsSpinner
        self.canCancel = canCancel
        self.canRetry = canRetry
        self.canDismiss = canDismiss
    }
}
