//
//  OrphanDetectionService.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData

/// At launch, books that synced down from iCloud may carry `isDownloaded == true` even though
/// the audio files don't exist on this device. This service reconciles that: any book whose
/// storage folder is empty or missing gets flipped to `isDownloaded = false` so the rest of the
/// app treats it as a Cloud Library orphan that needs re-acquisition.
enum OrphanDetectionService {
    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "OrphanDetection")

    static func runIfNeeded(modelContainer: ModelContainer) {
        Task.detached(priority: .utility) {
            await run(modelContainer: modelContainer)
        }
    }

    private static func run(modelContainer: ModelContainer) async {
        let context = ModelContext(modelContainer)
        guard let books = try? context.fetch(FetchDescriptor<Audiobook>()) else { return }

        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let libraryURL = appSupport.appendingPathComponent("Audiobooks", isDirectory: true)

        var flipped = 0
        for book in books where book.isDownloaded {
            // Streaming-only books legitimately have no folder; skip them.
            if book.tracks.contains(where: { $0.remoteURL != nil && $0.storedFileName.isEmpty }) { continue }

            let folderURL = libraryURL.appendingPathComponent(book.folderName, isDirectory: true)
            let exists = fm.fileExists(atPath: folderURL.path(percentEncoded: false))
            let contents = exists
                ? ((try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? [])
                : []
            let hasFiles = !contents.isEmpty

            log.info("Inspect local audiobook storage exists=\(exists, privacy: .public) hasFiles=\(hasFiles, privacy: .public) fileCount=\(contents.count, privacy: .public) trackCount=\(book.tracks.count, privacy: .public)")

            if !hasFiles {
                book.isDownloaded = false
                flipped += 1
            }
        }
        if flipped > 0 {
            try? context.save()
            log.info("Marked \(flipped, privacy: .public) book(s) as iCloud orphans missing local files")
        }
    }
}
