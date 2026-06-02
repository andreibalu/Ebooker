//
//  OrphanRestoreService.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Looks up cloud-synced "orphan" `Audiobook` rows whose audio files aren't present on this device,
/// and adopts a pending import into one of them (rewriting the file copies and track pointers so
/// the user's moments, progress, recap, and EQ flow back to the re-imported book).
enum OrphanRestoreService {
    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "OrphanRestore")

    /// Fetches Audiobook rows that look like orphans on this device:
    /// not downloaded, not streaming, not a free-book catalog entry.
    static func fetchOrphanCandidates(modelContext: ModelContext) -> [Audiobook] {
        guard let all = try? modelContext.fetch(FetchDescriptor<Audiobook>()) else { return [] }
        return all.filter { book in
            !book.isDownloaded && !book.isFreeBook
        }
    }

    /// Finds the orphan whose tracks best match the pending import by content fingerprint.
    /// Returns nil if no orphan has any matching fingerprint.
    static func findMatch(for pending: PendingImportSelection, modelContext: ModelContext) -> Audiobook? {
        let pendingFingerprints = Set(pending.tracks.compactMap { $0.contentFingerprint })
        guard !pendingFingerprints.isEmpty else { return nil }

        let orphans = fetchOrphanCandidates(modelContext: modelContext)
        var best: (book: Audiobook, hits: Int)? = nil
        for book in orphans {
            let orphanFingerprints = Set(book.tracks.compactMap { $0.contentFingerprint })
            let hits = orphanFingerprints.intersection(pendingFingerprints).count
            if hits == 0 { continue }
            if best == nil || hits > best!.hits {
                best = (book, hits)
            }
        }
        return best?.book
    }

    /// Copies the pending tracks into the orphan's existing storage folder, updates the
    /// `AudioTrack` records to point at the freshly imported files, refreshes durations,
    /// and flips `isDownloaded = true`.
    @discardableResult
    static func adopt(
        orphan: Audiobook,
        pending: PendingImportSelection,
        modelContext: ModelContext
    ) throws -> Audiobook {
        let folderURL = try storageFolderURL(for: orphan.folderName)
        // Clear out anything stale that happens to be in the folder before copying.
        let existing = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        for file in existing {
            try? FileManager.default.removeItem(at: file)
        }

        // Match each pending track to an existing AudioTrack by fingerprint first, then by index.
        let existingTracks = orphan.sortedTracks
        var consumedTrackIds = Set<UUID>()
        var rewrittenTracks: [AudioTrack] = []

        for (index, preview) in pending.tracks.enumerated() {
            let storedFileName = "\(String(format: "%03d", index + 1))-\(sanitizedFileName(preview.originalFileName))"
            let destinationURL = folderURL.appendingPathComponent(storedFileName, conformingTo: .audio)

            try copyFile(from: preview.sourceURL, to: destinationURL)

            // Prefer fingerprint match against an existing track; otherwise fall back to positional.
            let matchedExisting: AudioTrack? = {
                if let fp = preview.contentFingerprint {
                    if let exact = existingTracks.first(where: { $0.contentFingerprint == fp && !consumedTrackIds.contains($0.id) }) {
                        return exact
                    }
                }
                return existingTracks.indices.contains(index)
                    ? (consumedTrackIds.contains(existingTracks[index].id) ? nil : existingTracks[index])
                    : nil
            }()

            if let track = matchedExisting {
                track.storedFileName = storedFileName
                track.originalFileName = preview.originalFileName
                track.duration = preview.duration
                track.orderIndex = index
                track.contentFingerprint = preview.contentFingerprint ?? track.contentFingerprint
                track.remoteURLString = nil
                consumedTrackIds.insert(track.id)
                rewrittenTracks.append(track)
            } else {
                let newTrack = AudioTrack(
                    title: preview.title,
                    originalFileName: preview.originalFileName,
                    storedFileName: storedFileName,
                    orderIndex: index,
                    duration: preview.duration,
                    audiobook: orphan
                )
                newTrack.contentFingerprint = preview.contentFingerprint
                modelContext.insert(newTrack)
                orphan.tracks.append(newTrack)
                rewrittenTracks.append(newTrack)
            }
        }

        // Any leftover existing tracks (orphan had more chapters than the user re-imported) — drop them.
        for track in existingTracks where !consumedTrackIds.contains(track.id) {
            if let idx = orphan.tracks.firstIndex(where: { $0.id == track.id }) {
                orphan.tracks.remove(at: idx)
            }
            modelContext.delete(track)
        }

        orphan.totalDuration = orphan.sortedTracks.reduce(0) { $0 + $1.duration }
        orphan.isDownloaded = true

        // Adopt the cover from the import if the orphan doesn't already have one synced.
        if orphan.coverArtData == nil, let cover = pending.coverArtData {
            orphan.coverArtData = cover
        }

        try modelContext.save()
        let firstStored = rewrittenTracks.first?.storedFileName ?? ""
        let firstExists = !firstStored.isEmpty && FileManager.default.fileExists(
            atPath: folderURL.appendingPathComponent(firstStored).path(percentEncoded: false)
        )
        log.info("Adopted orphan '\(orphan.title, privacy: .public)' folder=\(folderURL.path(), privacy: .public) tracks=\(rewrittenTracks.count, privacy: .public) firstFileExists=\(firstExists, privacy: .public) isDownloaded=\(orphan.isDownloaded, privacy: .public)")
        return orphan
    }

    /// Merges a downloaded local book INTO a cloud-only entry (cloud-wins). Copies the local audio
    /// files into the cloud entry's folder and rewrites its track pointers (via `adopt`), then deletes
    /// the now-redundant local record. The SURVIVING record is `cloudEntry`, so its synced progress,
    /// moments, recap, and EQ are what the user keeps; the local book's divergent state is discarded.
    @discardableResult
    static func merge(
        localBook: Audiobook,
        into cloudEntry: Audiobook,
        modelContext: ModelContext
    ) throws -> Audiobook {
        // Build a pending import that points at the local book's on-disk files.
        let previews: [TrackImportPreview] = try localBook.sortedTracks.map { track in
            let url = try LibraryImportService.fileURL(for: track, in: localBook)
            return TrackImportPreview(
                sourceURL: url,
                title: track.title,
                originalFileName: track.originalFileName,
                duration: track.duration,
                contentFingerprint: track.contentFingerprint
            )
        }
        let pending = PendingImportSelection(
            sourceURLs: previews.map(\.sourceURL),
            suggestedTitle: localBook.title,
            suggestedAuthor: localBook.author,
            coverArtData: localBook.coverArtData,
            tracks: previews
        )

        _ = try adopt(orphan: cloudEntry, pending: pending, modelContext: modelContext)

        // Remove the duplicate local record and its (now-copied) files.
        try LibraryImportService.deleteAudiobook(localBook, deleteFiles: true, modelContext: modelContext)

        log.info("Merged local '\(localBook.title, privacy: .public)' into cloud entry '\(cloudEntry.title, privacy: .public)'")
        return cloudEntry
    }

    // MARK: - Free-book matching (by catalog id)

    /// Finds an archived free-book backup that matches a LibriVox catalog id — i.e. a free book the
    /// user removed from this device but kept in their iCloud Library. Used to auto-match on re-add
    /// and behind the manual "Match with iCloud backup" button. `catalogId` is computed over a private
    /// backing field, so it can't be expressed in a `#Predicate`; we filter in memory.
    static func fetchFreeBackup(catalogId: String, modelContext: ModelContext) -> Audiobook? {
        guard !catalogId.isEmpty else { return nil }
        guard let all = try? modelContext.fetch(FetchDescriptor<Audiobook>()) else { return nil }
        return all.first { $0.isFreeBook && $0.isArchived && $0.catalogId == catalogId }
    }

    /// Free-book analogue of `merge` (cloud-wins) with no files to copy: discards the just-added
    /// duplicate and brings the archived iCloud backup back into the library as a streaming entry,
    /// preserving its synced progress, moments, recap, and EQ. The surviving record is `backup`.
    static func restoreFreeBackup(
        replacing current: Audiobook,
        with backup: Audiobook,
        modelContext: ModelContext
    ) throws {
        backup.isArchived = false
        backup.isDownloaded = false
        try LibraryImportService.deleteAudiobook(current, deleteFiles: current.isDownloaded, modelContext: modelContext)
        log.info("Restored free backup '\(backup.title, privacy: .public)' (catalogId match), discarded duplicate '\(current.title, privacy: .public)'")
    }

    // MARK: - Private helpers (duplicated minimally from LibraryImportService to avoid widening its API)

    private static func storageFolderURL(for folderName: String) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let libraryURL = applicationSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let folder = libraryURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

    private static func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}
