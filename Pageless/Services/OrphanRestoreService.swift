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
        log.info("Adopted orphan '\(orphan.title, privacy: .public)' with \(rewrittenTracks.count, privacy: .public) track(s)")
        return orphan
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

        if FileManager.default.fileExists(atPath: destinationURL.path()) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}
