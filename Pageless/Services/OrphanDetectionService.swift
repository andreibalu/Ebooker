//
//  OrphanDetectionService.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData

/// Keeps this device's `DeviceDownloadState` true to the files on disk. Runs at launch and, while
/// sync is on, after each CloudKit import:
/// - A book with no entry yet (first launch after the update, or a record that just arrived from
///   another device) gets one from its files, whatever the legacy synced flag says.
/// - A downloaded book whose files are gone flips to not downloaded, so own imports become Cloud
///   Library orphans and server books streaming entries.
/// - Entries for deleted books are dropped.
/// Nothing here writes a synced field, so two devices can't undo each other's answer.
enum OrphanDetectionService {
    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "OrphanDetection")

    static func runIfNeeded(modelContainer: ModelContainer) {
        Task.detached(priority: .utility) {
            await run(modelContainer: modelContainer)
        }
    }

    /// Only books that claim local audio are inspected. Streaming entries — free books and books
    /// from the user's Audiobookshelf server — legitimately have no folder and are never orphans.
    static func needsLocalFileCheck(_ book: Audiobook) -> Bool {
        guard book.isDownloaded else { return false }
        if book.isAudiobookshelfBook { return true }
        return !book.tracks.contains(where: { $0.remoteURL != nil && $0.storedFileName.isEmpty })
    }

    static func shouldMarkOrphan(_ book: Audiobook, hasLocalFiles: Bool) -> Bool {
        needsLocalFileCheck(book) && !hasLocalFiles
    }

    static func run(modelContainer: ModelContainer, state: DeviceDownloadState = .shared) async {
        let context = ModelContext(modelContainer)
        guard let books = try? context.fetch(FetchDescriptor<Audiobook>()) else { return }

        var settled = 0
        var flipped = 0
        for book in books {
            if !state.hasEntry(book.id) {
                state.set(book.hasLocalAudio(), for: book.id)
                settled += 1
            } else if needsLocalFileCheck(book), shouldMarkOrphan(book, hasLocalFiles: book.hasLocalAudio()) {
                log.info("Downloaded book lost its local audio trackCount=\(book.tracks.count, privacy: .public)")
                book.isDownloaded = false
                flipped += 1
            }
        }
        state.retainOnly(Set(books.map(\.id)))
        if settled > 0 {
            log.info("Set this device's download state for \(settled, privacy: .public) book(s) from their files")
        }
        if flipped > 0 || settled > 0 {
            // A book that lost its audio leaves the library, so the widget may need the next one.
            await MainActor.run { ContinueListeningSnapshotWriter.shared.refresh(context: modelContainer.mainContext) }
        }
        if flipped > 0 {
            log.info("Marked \(flipped, privacy: .public) book(s) as missing local files")
        }
    }
}
