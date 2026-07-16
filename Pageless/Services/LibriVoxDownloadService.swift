//
//  LibriVoxDownloadService.swift
//  Pageless
//

import AVFoundation
import CryptoKit
import Foundation
import SwiftData

enum LibriVoxDownloadError: LocalizedError {
    case noTracks
    case invalidTrackURL(String)
    case couldNotCreateStorage
    case missingStagedFile(String)

    var errorDescription: String? {
        switch self {
        case .noTracks:
            "This book has no downloadable tracks."
        case .invalidTrackURL(let title):
            "Could not resolve a download URL for \"\(title)\"."
        case .couldNotCreateStorage:
            "The app could not create local storage for this audiobook."
        case .missingStagedFile(let fileName):
            "A staged download file is missing: \(fileName)."
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

    static func fileMetadata(at url: URL) throws -> LibriVoxDownloadFileMetadata {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        let chunkSize = 1024 * 1024
        while true {
            let chunk = try file.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
        return .init(
            byteCount: byteCount,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    static func fileMatchesMetadata(
        at url: URL,
        expected: LibriVoxDownloadFileMetadata,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)),
              let actual = try? fileMetadata(at: url)
        else { return false }
        return actual == expected
    }

    static func finalizeStagedFreshDownload(
        book: LibriVoxBook,
        job: LibriVoxDownloadJob,
        stagingFolderURL: URL,
        destinationFolderName: String? = nil,
        modelContext: ModelContext,
        beforeCommit: () throws -> Void
    ) throws -> Audiobook {
        let folderName = destinationFolderName ?? UUID().uuidString
        let folderURLWithoutCreate = try storageFolderURL(named: folderName)
        let folderExistedBeforeFinalization = FileManager.default.fileExists(
            atPath: folderURLWithoutCreate.path(percentEncoded: false)
        )
        let folderURL = try makeStorageFolder(named: folderName)
        do {
            let tracks = try job.tracks.enumerated().map { index, track in
                let source = stagingFolderURL.appendingPathComponent(track.storedFileName)
                let destination = folderURL.appendingPathComponent(track.storedFileName)
                if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                    let destinationIsValid = job.fileMetadata[index].map {
                        fileMatchesMetadata(at: destination, expected: $0)
                    } ?? false
                    if !destinationIsValid {
                        if FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) {
                            try FileManager.default.removeItem(at: destination)
                            try FileManager.default.moveItem(at: source, to: destination)
                        } else {
                            throw LibriVoxDownloadError.missingStagedFile(track.storedFileName)
                        }
                    }
                } else if FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) {
                    try FileManager.default.moveItem(at: source, to: destination)
                } else {
                    throw LibriVoxDownloadError.missingStagedFile(track.storedFileName)
                }
                guard let expected = job.fileMetadata[index],
                      fileMatchesMetadata(at: destination, expected: expected) else {
                    throw LibriVoxDownloadError.missingStagedFile(track.storedFileName)
                }
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
            if !folderExistedBeforeFinalization {
                try? FileManager.default.removeItem(at: folderURL)
            }
            throw error
        }
    }

    static func finalizeStagedExistingDownload(
        audiobook: Audiobook,
        job: LibriVoxDownloadJob,
        stagingFolderURL: URL,
        backupFolderURL: URL,
        modelContext: ModelContext,
        beforeCommit: () throws -> Void
    ) throws {
        let folderURL = try storageFolderURL(named: audiobook.folderName)
        let folderExistedBeforeFinalization = FileManager.default.fileExists(
            atPath: folderURL.path(percentEncoded: false)
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let tracks = audiobook.sortedTracks
        guard tracks.count == job.tracks.count else { throw LibriVoxDownloadError.noTracks }
        let trackSnapshots = tracks.map {
            ($0, $0.title, $0.originalFileName, $0.storedFileName, $0.duration, $0.remoteURLString)
        }
        let wasDownloaded = audiobook.isDownloaded
        let wasArchived = audiobook.isArchived
        let originalTotalDuration = audiobook.totalDuration
        var createdURLs: [URL] = []
        try FileManager.default.createDirectory(at: backupFolderURL, withIntermediateDirectories: true)
        var backups: [(original: URL, backup: URL)] = []
        do {
            for (index, pair) in zip(tracks, job.tracks).enumerated() {
                let (track, staged) = pair
                let source = stagingFolderURL.appendingPathComponent(staged.storedFileName)
                let destination = folderURL.appendingPathComponent(staged.storedFileName)
                let sourceExists = FileManager.default.fileExists(atPath: source.path(percentEncoded: false))
                let destinationExists = FileManager.default.fileExists(atPath: destination.path(percentEncoded: false))
                guard let expected = job.fileMetadata[index] else {
                    throw LibriVoxDownloadError.missingStagedFile(staged.storedFileName)
                }
                guard sourceExists || destinationExists else {
                    throw LibriVoxDownloadError.missingStagedFile(staged.storedFileName)
                }
                if sourceExists {
                    if destinationExists {
                        if fileMatchesMetadata(at: destination, expected: expected) {
                            try FileManager.default.removeItem(at: source)
                        } else {
                            let backup = backupFolderURL.appendingPathComponent(staged.storedFileName)
                            if !FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) {
                                try FileManager.default.copyItem(at: destination, to: backup)
                            }
                            backups.append((destination, backup))
                            try FileManager.default.removeItem(at: destination)
                            try FileManager.default.moveItem(at: source, to: destination)
                            createdURLs.append(destination)
                        }
                    } else {
                        try FileManager.default.moveItem(at: source, to: destination)
                        createdURLs.append(destination)
                    }
                } else {
                    if !fileMatchesMetadata(at: destination, expected: expected) {
                        let backup = backupFolderURL.appendingPathComponent(staged.storedFileName)
                        if FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) {
                            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                                try FileManager.default.removeItem(at: destination)
                            }
                            try FileManager.default.moveItem(at: backup, to: destination)
                        }
                    }
                    guard fileMatchesMetadata(at: destination, expected: expected) else {
                        throw LibriVoxDownloadError.missingStagedFile(staged.storedFileName)
                    }
                }
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
            for url in createdURLs { try? FileManager.default.removeItem(at: url) }
            for backup in backups {
                try? FileManager.default.removeItem(at: backup.original)
                try? FileManager.default.moveItem(at: backup.backup, to: backup.original)
            }
            try? FileManager.default.removeItem(at: backupFolderURL)
            if !folderExistedBeforeFinalization {
                try? FileManager.default.removeItem(at: folderURL)
            }
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
                if FreeBookIdentityService.hasCommittedAudioFiles(match.audiobook) {
                    if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: folderURL)
                    }
                    return match.audiobook
                }
                if match.audiobook.tracks.isEmpty {
                    if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: folderURL)
                    }
                    return match.audiobook
                }
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
        let dest = try storageFolderURL(named: folderName)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            throw LibriVoxDownloadError.couldNotCreateStorage
        }
        return dest
    }

    static func storageFolderURL(named folderName: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let booksDir = appSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        let dest = booksDir.appendingPathComponent(folderName, isDirectory: true)
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
