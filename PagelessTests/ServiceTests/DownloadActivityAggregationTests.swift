//
//  DownloadActivityAggregationTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct DownloadActivityAggregationTests {
    @Test func singleEntryUsesBookTitleAndFractionalTrackProgress() {
        let state = DownloadActivitySnapshot.aggregate(entries: [
            entry(title: "Jane Eyre", completed: 1, total: 4, current: 0.5)
        ])

        #expect(state?.title == "Jane Eyre")
        #expect(state?.activeBookCount == 1)
        #expect(state?.completedTracks == 1)
        #expect(state?.totalTracks == 4)
        #expect(state?.progress == 0.375)
        #expect(state?.phase == .downloading)
    }

    @Test func multipleEntriesUseTrackWeightedProgress() {
        let state = DownloadActivitySnapshot.aggregate(entries: [
            entry(title: "A", completed: 1, total: 2, current: 0.5),
            entry(title: "B", completed: 2, total: 6, current: 0)
        ])

        #expect(state?.title == "2 books downloading")
        #expect(state?.activeBookCount == 2)
        #expect(state?.completedTracks == 3)
        #expect(state?.totalTracks == 8)
        #expect(state?.progress == 0.4375)
    }

    @Test func fractionalProgressIsClamped() {
        let high = entry(completed: 1, total: 4, current: 2)
        let low = entry(completed: 1, total: 4, current: -2)

        #expect(high.progress == 0.5)
        #expect(low.progress == 0.25)
    }

    @Test func runnableEntriesTakePrecedenceOverFailures() {
        let state = DownloadActivitySnapshot.aggregate(entries: [
            entry(title: "Failed", phase: .failed, completed: 0, total: 2, error: "Offline"),
            entry(title: "Active", phase: .preparing, completed: 0, total: 0)
        ])

        #expect(state?.title == "Active")
        #expect(state?.phase == .preparing)
        #expect(state?.failureMessage == nil)
    }

    @Test func failedEntryUsesPausedCopyAndRetainsError() {
        let state = DownloadActivitySnapshot.aggregate(entries: [
            entry(title: "Jane Eyre", phase: .failed, completed: 1, total: 4, error: "Offline")
        ])

        #expect(state?.title == "Download paused")
        #expect(state?.phase == .failed)
        #expect(state?.failureMessage == "Offline")
    }

    private func entry(
        title: String = "Book",
        phase: LibriVoxDownloadManager.Phase = .downloading,
        completed: Int,
        total: Int,
        current: Double = 0,
        error: String? = nil
    ) -> LibriVoxDownloadManager.Entry {
        .init(
            request: .init(
                catalogID: title,
                metadata: .init(title: title),
                target: .fresh
            ),
            phase: phase,
            completedTracks: completed,
            totalTracks: total,
            currentTrackFraction: current,
            errorMessage: error
        )
    }
}
