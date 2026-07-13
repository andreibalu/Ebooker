//
//  CloudLibraryRestoreTests.swift
//  PagelessTests
//

import Foundation
import Testing
import SwiftData
@testable import Pageless

@MainActor
struct CloudLibraryRestoreTests {
    @Test func exactFingerprintMultisetRoutesStraightToAdoption() {
        let pending = makePending(fingerprints: ["chapter-a", "chapter-b"])
        let book = makeBook(fingerprints: ["chapter-b", "chapter-a"])

        #expect(CloudLibraryView.restoreDecision(pending: pending, for: book) == .adopt)
    }

    @Test func partialFingerprintOverlapRequiresExplicitConfirmation() {
        let pending = makePending(fingerprints: ["shared", "pending-only"])
        let book = makeBook(fingerprints: ["shared", "existing-only"])

        #expect(CloudLibraryView.restoreDecision(pending: pending, for: book) == .confirmMismatch)
    }

    @Test func repeatedFingerprintCountMismatchRequiresExplicitConfirmation() {
        let pending = makePending(fingerprints: ["repeated", "repeated", "other"])
        let book = makeBook(fingerprints: ["other", "other", "repeated"])

        #expect(CloudLibraryView.restoreDecision(pending: pending, for: book) == .confirmMismatch)
    }

    @Test func missingFingerprintRequiresExplicitConfirmation() {
        let pending = makePending(fingerprints: ["chapter-a", nil])
        let book = makeBook(fingerprints: ["chapter-a", "chapter-b"])

        #expect(CloudLibraryView.restoreDecision(pending: pending, for: book) == .confirmMismatch)
    }

    @Test func mismatchDoesNotAdoptBeforeConfirmationAndCancelReleasesAccess() throws {
        let flow = CloudLibraryRestoreFlow()
        let pending = makePending(fingerprints: ["pending-only"])
        let book = makeBook(fingerprints: ["existing-only"])
        let url = URL(fileURLWithPath: "/tmp/mismatch.m4a")
        var adoptCount = 0
        var releaseCount = 0

        let decision = try flow.route(
            pending: pending,
            for: book,
            accessedURLs: [url],
            adopt: { _, _ in adoptCount += 1 },
            release: { _ in releaseCount += 1 }
        )

        #expect(decision == .confirmMismatch)
        #expect(adoptCount == 0)
        #expect(releaseCount == 0)

        flow.cancel { _ in releaseCount += 1 }

        #expect(flow.pending == nil)
        #expect(adoptCount == 0)
        #expect(releaseCount == 1)
    }

    @Test func exactRouteAdoptsOnceAndReleasesAccess() throws {
        let flow = CloudLibraryRestoreFlow()
        let pending = makePending(fingerprints: ["same"])
        let book = makeBook(fingerprints: ["same"])
        var adoptCount = 0
        var releaseCount = 0

        let decision = try flow.route(
            pending: pending,
            for: book,
            accessedURLs: [URL(fileURLWithPath: "/tmp/exact.m4a")],
            adopt: { _, _ in adoptCount += 1 },
            release: { _ in releaseCount += 1 }
        )

        #expect(decision == .adopt)
        #expect(adoptCount == 1)
        #expect(releaseCount == 1)
        #expect(flow.pending == nil)
    }

    @Test func confirmationAdoptsExactlyOnceAndReleasesAccess() throws {
        let flow = CloudLibraryRestoreFlow()
        let pending = makePending(fingerprints: ["shared", "pending-only"])
        let book = makeBook(fingerprints: ["shared", "existing-only"])
        var adoptCount = 0
        var releaseCount = 0

        _ = try flow.route(
            pending: pending,
            for: book,
            accessedURLs: [URL(fileURLWithPath: "/tmp/mismatch.m4a")],
            adopt: { _, _ in adoptCount += 1 },
            release: { _ in releaseCount += 1 }
        )
        try flow.confirm(
            adopt: { _, _ in adoptCount += 1 },
            release: { _ in releaseCount += 1 }
        )
        try flow.confirm(
            adopt: { _, _ in adoptCount += 1 },
            release: { _ in releaseCount += 1 }
        )

        #expect(adoptCount == 1)
        #expect(releaseCount == 1)
        #expect(flow.pending == nil)
    }

    @Test func failedConfirmationKeepsRequestAndAccessForRetry() throws {
        let flow = CloudLibraryRestoreFlow()
        let pending = makePending(fingerprints: ["shared", "pending-only"])
        let book = makeBook(fingerprints: ["shared", "existing-only"])
        var shouldFail = true
        var adoptCount = 0
        var releaseCount = 0

        _ = try flow.route(
            pending: pending,
            for: book,
            accessedURLs: [URL(fileURLWithPath: "/tmp/mismatch.m4a")],
            adopt: { _, _ in },
            release: { _ in releaseCount += 1 }
        )

        do {
            try flow.confirm(
                adopt: { _, _ in
                    adoptCount += 1
                    if shouldFail { throw RestoreFlowTestError.failed }
                },
                release: { _ in releaseCount += 1 }
            )
            Issue.record("Expected confirmation failure")
        } catch RestoreFlowTestError.failed {
            // Expected: request remains retryable.
        }

        #expect(flow.pending != nil)
        #expect(adoptCount == 1)
        #expect(releaseCount == 0)

        shouldFail = false
        try flow.confirm(
            adopt: { _, _ in adoptCount += 1 },
            release: { _ in releaseCount += 1 }
        )

        #expect(adoptCount == 2)
        #expect(releaseCount == 1)
        #expect(flow.pending == nil)
    }

    private enum RestoreFlowTestError: Error {
        case failed
    }

    private func makePending(fingerprints: [String?]) -> PendingImportSelection {
        let tracks = fingerprints.enumerated().map { index, fingerprint in
            TrackImportPreview(
                sourceURL: URL(fileURLWithPath: "/tmp/cloud-restore-\(index).m4a"),
                title: "Chapter \(index + 1)",
                originalFileName: "chapter-\(index + 1).m4a",
                duration: 60,
                contentFingerprint: fingerprint
            )
        }
        return PendingImportSelection(
            sourceURLs: tracks.map(\.sourceURL),
            suggestedTitle: "Imported Book",
            suggestedAuthor: "",
            coverArtData: nil,
            tracks: tracks
        )
    }

    private func makeBook(fingerprints: [String?]) -> Audiobook {
        let book = Audiobook(title: "Cloud Book", folderName: UUID().uuidString, isDownloaded: false)
        for (index, fingerprint) in fingerprints.enumerated() {
            let track = AudioTrack(
                title: "Chapter \(index + 1)",
                originalFileName: "chapter-\(index + 1).m4a",
                storedFileName: "chapter-\(index + 1).m4a",
                orderIndex: index,
                duration: 60,
                audiobook: book
            )
            track.contentFingerprint = fingerprint
            book.tracks.append(track)
        }
        return book
    }
}
