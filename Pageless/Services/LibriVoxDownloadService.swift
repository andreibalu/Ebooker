//
//  LibriVoxDownloadService.swift
//  Pageless
//

import AVFoundation
import Foundation
import SwiftData

enum LibriVoxDownloadError: LocalizedError {
    case noTracks
    case invalidTrackURL(String)
    case couldNotCreateStorage

    var errorDescription: String? {
        switch self {
        case .noTracks:
            "This book has no downloadable tracks."
        case .invalidTrackURL(let title):
            "Could not resolve a download URL for \"\(title)\"."
        case .couldNotCreateStorage:
            "The app could not create local storage for this audiobook."
        }
    }
}

enum LibriVoxDownloadService {
    typealias ProgressHandler = (_ completed: Int, _ total: Int) -> Void

    /// Fetches the track list for a LibriVox project without downloading anything.
    static func prepareDownload(projectID: String) async throws -> [LibriVoxAPITrack] {
        let tracks = try await LibriVoxAPIClient.fetchTracks(projectID: projectID)
        guard !tracks.isEmpty else { throw LibriVoxDownloadError.noTracks }
        return tracks
    }

    static func storedFileName(title: String, remoteURL: URL, index: Int) -> String {
        let safeTitle = title.isEmpty ? "Track \(index + 1)" : title
        let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        return "\(String(format: "%03d", index + 1))-\(sanitized(safeTitle)).\(ext)"
    }

    static func finalizeStagedFreshDownload(
        book: LibriVoxBook,
        job: LibriVoxDownloadJob,
        stagingFolderURL: URL,
        modelContext: ModelContext,
        beforeCommit: () throws -> Void
    ) throws -> Audiobook {
        let folderName = UUID().uuidString
        let folderURL = try makeStorageFolder(named: folderName)
        do {
            let tracks = try job.tracks.enumerated().map { index, track in
                let source = stagingFolderURL.appendingPathComponent(track.storedFileName)
                let destination = folderURL.appendingPathComponent(track.storedFileName)
                try FileManager.default.moveItem(at: source, to: destination)
                let saved = AudioTrack(
                    title: track.title,
                    originalFileName: track.remoteURL.lastPathComponent,
                    storedFileName: track.storedFileName,
                    orderIndex: index,
                    duration: track.durationSeconds
                )
                saved.remoteURLString = track.remoteURL.absoluteString
                return saved
            }
            try beforeCommit()
            return try finalizeDownloadedBook(
                book: book,
                folderName: folderName,
                folderURL: folderURL,
                audioTracks: tracks,
                modelContext: modelContext
            )
        } catch {
            try? FileManager.default.removeItem(at: folderURL)
            throw error
        }
    }

    static func finalizeStagedExistingDownload(
        audiobook: Audiobook,
        job: LibriVoxDownloadJob,
        stagingFolderURL: URL,
        modelContext: ModelContext,
        beforeCommit: () throws -> Void
    ) throws {
        let folderURL = try makeStorageFolder(named: audiobook.folderName)
        let tracks = audiobook.sortedTracks
        guard tracks.count == job.tracks.count else { throw LibriVoxDownloadError.noTracks }
        let trackSnapshots = tracks.map {
            ($0, $0.title, $0.originalFileName, $0.storedFileName, $0.duration, $0.remoteURLString)
        }
        let wasDownloaded = audiobook.isDownloaded
        let wasArchived = audiobook.isArchived
        let originalTotalDuration = audiobook.totalDuration
        var movedURLs: [URL] = []
        do {
            for (track, staged) in zip(tracks, job.tracks) {
                let source = stagingFolderURL.appendingPathComponent(staged.storedFileName)
                let destination = folderURL.appendingPathComponent(staged.storedFileName)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: source, to: destination)
                movedURLs.append(destination)
                track.title = staged.title
                track.originalFileName = staged.remoteURL.lastPathComponent
                track.storedFileName = staged.storedFileName
                track.duration = staged.durationSeconds
                track.remoteURLString = staged.remoteURL.absoluteString
            }
            try beforeCommit()
            audiobook.isDownloaded = true
            audiobook.isArchived = false
            audiobook.totalDuration = tracks.reduce(0) { $0 + $1.duration }
            try modelContext.save()
        } catch {
            for (track, title, originalFileName, storedFileName, duration, remoteURLString) in trackSnapshots {
                track.title = title
                track.originalFileName = originalFileName
                track.storedFileName = storedFileName
                track.duration = duration
                track.remoteURLString = remoteURLString
            }
            audiobook.isDownloaded = wasDownloaded
            audiobook.isArchived = wasArchived
            audiobook.totalDuration = originalTotalDuration
            for url in movedURLs { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    /// Downloads all tracks, fetches cover art, and imports the book into the SwiftData library.
    /// Returns the newly created Audiobook so the caller can navigate to it.
    static func downloadAndImport(
        book: LibriVoxBook,
        tracks: [LibriVoxAPITrack],
        modelContext: ModelContext,
        onProgress: @escaping ProgressHandler
    ) async throws -> Audiobook {
        try await downloadAndImport(
            book: book,
            tracks: tracks,
            modelContext: modelContext,
            onProgress: onProgress,
            downloadToTemporaryFile: { remoteURL in
                let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
                return temporaryURL
            },
            beforeCommit: {},
            saveModelContext: { try $0.save() }
        )
    }

    /// Injectable boundaries make the final-file / pre-commit cancellation window deterministic.
    static func downloadAndImport(
        book: LibriVoxBook,
        tracks: [LibriVoxAPITrack],
        modelContext: ModelContext,
        onProgress: @escaping ProgressHandler,
        downloadToTemporaryFile: @escaping (URL) async throws -> URL,
        beforeCommit: @escaping () -> Void,
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) async throws -> Audiobook {
        if let match = try FreeBookIdentityService.match(
            catalogId: book.id,
            modelContext: modelContext
        ), match.classification == .downloadedActive {
            return match.audiobook
        }

        let folderName = UUID().uuidString
        let folderURL = try makeStorageFolder(named: folderName)

        do {
            // LibriVox cover URLs are unreliable — skip the fetch and let the
            // generated letter template render in every cover surface instead.

            // Download each track
            var audioTracks: [AudioTrack] = []
            for (index, track) in tracks.enumerated() {
                guard !track.listenURL.isEmpty, let remoteURL = URL(string: track.listenURL) else {
                    throw LibriVoxDownloadError.invalidTrackURL(track.title)
                }

                let safeTitle = track.title.isEmpty ? "Track \(index + 1)" : track.title
                let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
                let storedFileName = "\(String(format: "%03d", index + 1))-\(sanitized(safeTitle)).\(ext)"
                let destURL = folderURL.appendingPathComponent(storedFileName)

                let tempURL = try await downloadToTemporaryFile(remoteURL)
                // Move from temp location (URLSession cleans up temp automatically on move)
                if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                let audioTrack = AudioTrack(
                    title: safeTitle,
                    originalFileName: remoteURL.lastPathComponent,
                    storedFileName: storedFileName,
                    orderIndex: index,
                    duration: track.durationSeconds
                )
                // Keep the streaming URL even though we downloaded a local copy: if the user later
                // removes the download, the book stays a streamable free-book backup in iCloud and
                // can be re-streamed or re-downloaded without re-resolving the catalog.
                audioTrack.remoteURLString = track.listenURL
                audioTracks.append(audioTrack)

                onProgress(index + 1, tracks.count)
            }

            beforeCommit()
            try Task.checkCancellation()
            return try finalizeDownloadedBook(
                book: book,
                folderName: folderName,
                folderURL: folderURL,
                audioTracks: audioTracks,
                modelContext: modelContext,
                saveModelContext: saveModelContext
            )

        } catch {
            // Clean up partial download folder on failure
            try? FileManager.default.removeItem(at: folderURL)
            throw error
        }
    }

    /// Downloads all tracks for a streaming-only audiobook that's already in the library.
    /// Updates existing AudioTrack entities in place to preserve playback state.
    static func downloadStreamedBook(
        audiobook: Audiobook,
        modelContext: ModelContext,
        onProgress: @escaping ProgressHandler
    ) async throws {
        try await downloadStreamedBook(
            audiobook: audiobook,
            modelContext: modelContext,
            onProgress: onProgress,
            downloadToTemporaryFile: { remoteURL in
                let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
                return temporaryURL
            }
        )
    }

    /// Injectable transport seam keeps cancellation/failure rollback deterministic in tests.
    static func downloadStreamedBook(
        audiobook: Audiobook,
        modelContext: ModelContext,
        onProgress: @escaping ProgressHandler,
        downloadToTemporaryFile: @escaping (URL) async throws -> URL
    ) async throws {
        try await downloadStreamedBook(
            audiobook: audiobook,
            modelContext: modelContext,
            onProgress: onProgress,
            downloadToTemporaryFile: downloadToTemporaryFile,
            beforeCommit: {},
            saveModelContext: { try $0.save() }
        )
    }

    static func downloadStreamedBook(
        audiobook: Audiobook,
        modelContext: ModelContext,
        onProgress: @escaping ProgressHandler,
        downloadToTemporaryFile: @escaping (URL) async throws -> URL,
        beforeCommit: @escaping () -> Void,
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) async throws {
        let folderURL = try makeStorageFolder(named: audiobook.folderName)
        let sortedTracks = audiobook.sortedTracks
        let trackSnapshots = sortedTracks.map {
            ($0, $0.originalFileName, $0.storedFileName, $0.duration)
        }
        let wasDownloaded = audiobook.isDownloaded
        let wasArchived = audiobook.isArchived
        let originalTotalDuration = audiobook.totalDuration

        do {
            var stagedMetadata: [(AudioTrack, String, String, TimeInterval)] = []
            for (index, track) in sortedTracks.enumerated() {
                guard let remoteURL = track.remoteURL else {
                    throw LibriVoxDownloadError.invalidTrackURL(track.title)
                }

                let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
                let safeTitle = track.title.isEmpty ? "Track_\(index + 1)" : track.title
                let storedFileName = "\(String(format: "%03d", index + 1))-\(sanitized(safeTitle)).\(ext)"
                let destURL = folderURL.appendingPathComponent(storedFileName)

                let tempURL = try await downloadToTemporaryFile(remoteURL)
                if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                var duration = track.duration
                let asset = AVURLAsset(url: destURL)
                if let dur = try? await asset.load(.duration), dur.seconds.isFinite, dur.seconds > 0 {
                    duration = dur.seconds
                }
                stagedMetadata.append((track, remoteURL.lastPathComponent, storedFileName, duration))

                onProgress(index + 1, sortedTracks.count)
            }

            beforeCommit()
            try Task.checkCancellation()
            for (track, originalFileName, storedFileName, duration) in stagedMetadata {
                track.originalFileName = originalFileName
                track.storedFileName = storedFileName
                track.duration = duration
            }
            audiobook.isDownloaded = true
            audiobook.isArchived = false
            audiobook.totalDuration = sortedTracks.reduce(0) { $0 + $1.duration }
            try saveModelContext(modelContext)
        } catch {
            for (track, originalFileName, storedFileName, duration) in trackSnapshots {
                track.originalFileName = originalFileName
                track.storedFileName = storedFileName
                track.duration = duration
            }
            audiobook.isDownloaded = wasDownloaded
            audiobook.isArchived = wasArchived
            audiobook.totalDuration = originalTotalDuration
            // Clean up partial downloads on failure
            try? FileManager.default.removeItem(at: folderURL)
            throw error
        }
    }

    // MARK: - Private helpers

    /// Resolves the identity race after files exist. Downloaded rows win and discard the fresh
    /// folder; streaming/archived rows absorb the files while preserving their book identity.
    static func finalizeDownloadedBook(
        book: LibriVoxBook,
        folderName: String,
        folderURL: URL,
        audioTracks: [AudioTrack],
        modelContext: ModelContext,
        saveModelContext: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Audiobook {
        if let match = try FreeBookIdentityService.match(catalogId: book.id, modelContext: modelContext) {
            switch match.classification {
            case .downloadedActive:
                if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: folderURL)
                }
                return match.audiobook
            case .streamingActive, .archived:
                return try FreeBookIdentityService.promoteToDownloaded(
                    match.audiobook,
                    folderName: folderName,
                    title: book.title,
                    author: book.authorDisplay,
                    coverArtData: nil,
                    tracks: audioTracks,
                    modelContext: modelContext,
                    saveModelContext: saveModelContext
                )
            }
        }

        let audiobook = Audiobook(
            title: book.title,
            author: book.authorDisplay,
            folderName: folderName,
            coverArtData: nil,
            totalDuration: audioTracks.reduce(0) { $0 + $1.duration },
            isFreeBook: true,
            catalogId: book.id
        )
        modelContext.insert(audiobook)
        for track in audioTracks {
            track.audiobook = audiobook
            modelContext.insert(track)
            audiobook.tracks.append(track)
        }
        do {
            try saveModelContext(modelContext)
            return audiobook
        } catch {
            audiobook.tracks.removeAll()
            for track in audioTracks {
                track.audiobook = nil
                modelContext.delete(track)
            }
            modelContext.delete(audiobook)
            throw error
        }
    }

    private static func makeStorageFolder(named folderName: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let booksDir = appSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        let dest = booksDir.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            throw LibriVoxDownloadError.couldNotCreateStorage
        }
        return dest
    }

    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:.")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}
