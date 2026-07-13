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
        modelContext: ModelContext,
        mutationEnvironment: LibraryMutationEnvironment = .live()
    ) throws -> Audiobook {
        let transaction = try LibraryMutationTransaction(environment: mutationEnvironment)
        do {
            let prepared = try prepareAdoption(
                orphan: orphan,
                pending: pending,
                modelContext: modelContext,
                transaction: transaction
            )
            try mutationEnvironment.save(modelContext)
            do {
                try transaction.commit()
            } catch {
                throw LibraryMutationError.modelCommittedButTransactionMarkerFailed(error)
            }
            let firstExists = !prepared.firstStored.isEmpty && FileManager.default.fileExists(
                atPath: prepared.folderURL.appendingPathComponent(prepared.firstStored).path(percentEncoded: false)
            )
            log.info("Adopted orphan tracks=\(prepared.trackCount) firstFileExists=\(firstExists) isDownloaded=\(orphan.isDownloaded)")
            return orphan
        } catch {
            if case LibraryMutationError.modelCommittedButTransactionMarkerFailed = error {
                throw error
            }
            try LibraryMutationTransaction.rollbackAndRethrow(
                error,
                modelContext: modelContext,
                transaction: transaction
            )
        }
    }

    /// Merges a downloaded local book INTO a cloud-only entry (cloud-wins). Copies the local audio
    /// files into the cloud entry's folder and rewrites its track pointers (via `adopt`), then deletes
    /// the now-redundant local record. The SURVIVING record is `cloudEntry`, so its synced progress,
    /// moments, recap, and EQ are what the user keeps; the local book's divergent state is discarded.
    @discardableResult
    static func merge(
        localBook: Audiobook,
        into cloudEntry: Audiobook,
        modelContext: ModelContext,
        mutationEnvironment: LibraryMutationEnvironment = .live()
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

        let transaction = try LibraryMutationTransaction(environment: mutationEnvironment)
        do {
            let prepared = try prepareAdoption(
                orphan: cloudEntry,
                pending: pending,
                modelContext: modelContext,
                transaction: transaction
            )
            let localFolder = try LibraryMutationTransaction.folderURL(
                for: localBook.folderName,
                rootURL: transaction.rootURL
            )
            if localFolder != prepared.folderURL {
                try transaction.backupExistingFolder(at: localFolder)
            }
            modelContext.delete(localBook)
            try mutationEnvironment.save(modelContext)
            do {
                try transaction.commit()
            } catch {
                throw LibraryMutationError.modelCommittedButTransactionMarkerFailed(error)
            }

            log.info("Merged local book into cloud entry")
            return cloudEntry
        } catch {
            if case LibraryMutationError.modelCommittedButTransactionMarkerFailed = error {
                throw error
            }
            try LibraryMutationTransaction.rollbackAndRethrow(
                error,
                modelContext: modelContext,
                transaction: transaction
            )
        }
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

    // MARK: - Private helpers

    private static func prepareAdoption(
        orphan: Audiobook,
        pending: PendingImportSelection,
        modelContext: ModelContext,
        transaction: LibraryMutationTransaction
    ) throws -> (folderURL: URL, trackCount: Int, firstStored: String) {
        let existingTracks = orphan.sortedTracks
        let storedFileNames = pending.tracks.enumerated().map { index, preview in
            "\(String(format: "%03d", index + 1))-\(sanitizedFileName(preview.originalFileName))"
        }
        for (preview, storedFileName) in zip(pending.tracks, storedFileNames) {
            _ = try transaction.stageCopy(from: preview.sourceURL, named: storedFileName)
        }

        let folderURL = try LibraryMutationTransaction.folderURL(
            for: orphan.folderName,
            rootURL: transaction.rootURL
        )
        try transaction.backupExistingFolder(at: folderURL)
        try transaction.promoteStaging(to: folderURL)

        var consumedTrackIds = Set<UUID>()
        var rewrittenTracks: [AudioTrack] = []
        for (index, preview) in pending.tracks.enumerated() {
            let storedFileName = storedFileNames[index]
            let matchedExisting: AudioTrack? = {
                if let fp = preview.contentFingerprint {
                    if let exact = existingTracks.first(where: {
                        $0.contentFingerprint == fp && !consumedTrackIds.contains($0.id)
                    }) {
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

        for track in existingTracks where !consumedTrackIds.contains(track.id) {
            if let index = orphan.tracks.firstIndex(where: { $0.id == track.id }) {
                orphan.tracks.remove(at: index)
            }
            modelContext.delete(track)
        }

        orphan.totalDuration = orphan.sortedTracks.reduce(0) { $0 + $1.duration }
        orphan.isDownloaded = true
        if orphan.coverArtData == nil, let cover = pending.coverArtData {
            orphan.coverArtData = cover
        }

        return (
            folderURL: folderURL,
            trackCount: rewrittenTracks.count,
            firstStored: rewrittenTracks.first?.storedFileName ?? ""
        )
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

}
