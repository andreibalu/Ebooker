//
//  LibraryImportService.swift
//  Pageless
//

import AVFoundation
import CryptoKit
import Foundation
import SwiftData

struct PendingImportSelection: Identifiable {
    let id = UUID()
    let sourceURLs: [URL]
    let suggestedTitle: String
    let suggestedAuthor: String
    let coverArtData: Data?
    let tracks: [TrackImportPreview]

    var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }
}

struct TrackImportPreview: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let title: String
    let originalFileName: String
    let duration: Double
    /// SHA-256 hex digest used to auto-match against an orphan cloud-synced book on re-import.
    /// Computed during `prepareImport`; nil when the file can't be read for fingerprinting.
    let contentFingerprint: String?
}

enum LibraryImportError: LocalizedError {
    case noAudioFiles
    case couldNotReadFile(URL)
    case couldNotCreateStorage
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .noAudioFiles:
            "Choose at least one audio file to create an audiobook."
        case .couldNotReadFile(let url):
            "The file \(url.lastPathComponent) could not be accessed."
        case .couldNotCreateStorage:
            "The app could not create local storage for this audiobook."
        case .invalidTitle:
            "Give the audiobook a title before importing it."
        }
    }
}

private struct ExtractedTrackMetadata {
    var title: String?
    var artist: String?
    var albumName: String?
    var artworkData: Data?
}

enum LibraryImportService {
    static func prepareImport(from urls: [URL]) async throws -> PendingImportSelection {
        let audioURLs = urls
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !audioURLs.isEmpty else {
            throw LibraryImportError.noAudioFiles
        }

        var previews: [TrackImportPreview] = []
        var metadatas: [ExtractedTrackMetadata] = []

        for url in audioURLs {
            let (duration, metadata) = try await loadDurationAndMetadata(for: url)
            metadatas.append(metadata)

            let embeddedTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trackTitle = (embeddedTitle?.isEmpty == false ? embeddedTitle! : url.deletingPathExtension().lastPathComponent)
            let fingerprint = await fingerprint(url: url, durationSeconds: duration)

            previews.append(
                TrackImportPreview(
                    sourceURL: url,
                    title: trackTitle,
                    originalFileName: url.lastPathComponent,
                    duration: duration,
                    contentFingerprint: fingerprint
                )
            )
        }

        let coverArtData = metadatas.compactMap(\.artworkData).first
        let suggestedAuthor = metadatas
            .compactMap { $0.artist?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let suggestedTitle = suggestedTitle(from: metadatas, audioURLs: audioURLs)

        return PendingImportSelection(
            sourceURLs: audioURLs,
            suggestedTitle: suggestedTitle,
            suggestedAuthor: suggestedAuthor,
            coverArtData: coverArtData,
            tracks: previews
        )
    }

    private static func suggestedTitle(
        from metadatas: [ExtractedTrackMetadata],
        audioURLs: [URL]
    ) -> String {
        let albumNames = metadatas
            .compactMap { $0.albumName?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniqueAlbums = Set(albumNames)
        if uniqueAlbums.count == 1, let album = uniqueAlbums.first {
            return album
        }

        if audioURLs.count == 1,
           let single = metadatas.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !single.isEmpty {
            return single
        }

        return titleSuggestion(for: audioURLs)
    }

    @discardableResult
    static func importAudiobook(
        from pending: PendingImportSelection,
        title: String,
        author: String,
        modelContext: ModelContext
    ) throws -> Audiobook {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw LibraryImportError.invalidTitle
        }

        let folderName = UUID().uuidString
        let folderURL = try storageFolderURL(for: folderName)

        let audiobook = Audiobook(
            title: trimmedTitle,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            folderName: folderName,
            coverArtData: pending.coverArtData,
            totalDuration: pending.totalDuration
        )

        modelContext.insert(audiobook)

        for (index, track) in pending.tracks.enumerated() {
            let storedFileName = "\(String(format: "%03d", index + 1))-\(sanitizedFileName(from: track.originalFileName))"
            let destinationURL = folderURL.appendingPathComponent(storedFileName, conformingTo: .audio)

            try copyFile(from: track.sourceURL, to: destinationURL)

            let savedTrack = AudioTrack(
                title: track.title,
                originalFileName: track.originalFileName,
                storedFileName: storedFileName,
                orderIndex: index,
                duration: track.duration,
                audiobook: audiobook
            )
            savedTrack.contentFingerprint = track.contentFingerprint

            audiobook.tracks.append(savedTrack)
            modelContext.insert(savedTrack)
        }

        audiobook.totalDuration = audiobook.sortedTracks.reduce(0) { $0 + $1.duration }
        try modelContext.save()

        return audiobook
    }

    static func deleteAudiobook(
        _ audiobook: Audiobook,
        deleteFiles: Bool,
        modelContext: ModelContext
    ) throws {
        if deleteFiles {
            let folderURL = try storageFolderURL(for: audiobook.folderName)
            if FileManager.default.fileExists(atPath: folderURL.path()) {
                try FileManager.default.removeItem(at: folderURL)
            }
        }

        modelContext.delete(audiobook)
        try modelContext.save()
    }

    static func fileURL(for track: AudioTrack, in audiobook: Audiobook) throws -> URL {
        try storageFolderURL(for: audiobook.folderName).appendingPathComponent(track.storedFileName)
    }

    /// Returns the total on-disk size of an audiobook's storage folder in megabytes, or nil if unavailable.
    static func folderSizeMB(for audiobook: Audiobook) -> Int? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }

        let folderURL = appSupport
            .appendingPathComponent("Audiobooks", isDirectory: true)
            .appendingPathComponent(audiobook.folderName, isDirectory: true)

        guard FileManager.default.fileExists(atPath: folderURL.path()) else { return nil }

        var totalBytes: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalBytes += Int64(size)
            }
        }

        guard totalBytes > 0 else { return nil }
        return Int(totalBytes / (1024 * 1024))
    }

    private static func titleSuggestion(for urls: [URL]) -> String {
        guard let firstURL = urls.first else { return "Imported Audiobook" }

        if urls.count == 1 {
            return firstURL.deletingPathExtension().lastPathComponent
        }

        let parentDirectories = Set(urls.map { $0.deletingLastPathComponent().lastPathComponent })
        if parentDirectories.count == 1, let directoryName = parentDirectories.first, !directoryName.isEmpty {
            return directoryName
        }

        return firstURL.deletingPathExtension().lastPathComponent
    }

    // MARK: - Content fingerprint (iCloud auto-match)

    /// SHA-256 hex digest of (first 1MB || last 1MB || u64LE(fileSize) || u64LE(durationMs)).
    /// Files at most 2MB get hashed in full. Returns nil if the file can't be read.
    /// Off the main thread — called from `prepareImport` and from the orphan-match probe.
    static func fingerprint(url: URL, durationSeconds: Double? = nil) async -> String? {
        return await Task.detached(priority: .utility) { () -> String? in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }

            let size: UInt64
            do { size = try handle.seekToEnd() } catch { return nil }
            do { try handle.seek(toOffset: 0) } catch { return nil }

            let chunkSize: UInt64 = 1024 * 1024 // 1MB
            var hasher = SHA256()

            if size <= chunkSize * 2 {
                if let data = try? handle.read(upToCount: Int(size)) {
                    hasher.update(data: data)
                }
            } else {
                if let head = try? handle.read(upToCount: Int(chunkSize)) {
                    hasher.update(data: head)
                }
                do { try handle.seek(toOffset: size - chunkSize) } catch { return nil }
                if let tail = try? handle.read(upToCount: Int(chunkSize)) {
                    hasher.update(data: tail)
                }
            }

            var sizeLE = size.littleEndian
            withUnsafeBytes(of: &sizeLE) { hasher.update(bufferPointer: $0) }

            let duration = durationSeconds ?? probeDurationSync(url: url)
            var durationMs = UInt64(max(0, duration * 1000)).littleEndian
            withUnsafeBytes(of: &durationMs) { hasher.update(bufferPointer: $0) }

            return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        }.value
    }

    /// Best-effort blocking duration probe used when a fingerprint is being computed for an existing
    /// file (e.g. backfill) without going back to AVURLAsset's async API.
    private static func probeDurationSync(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let cmtime = asset.duration
        let seconds = CMTimeGetSeconds(cmtime)
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    private static func measureDuration(for url: URL) async throws -> Double {
        try await withSecurityScopedAccess(to: url) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            return max(duration.seconds, 0)
        }
    }

    private static func loadDurationAndMetadata(for url: URL) async throws -> (Double, ExtractedTrackMetadata) {
        try await withSecurityScopedAccess(to: url) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let metadata = await extractMetadata(from: asset)
            return (max(duration.seconds, 0), metadata)
        }
    }

    private static func extractMetadata(from asset: AVURLAsset) async -> ExtractedTrackMetadata {
        var meta = ExtractedTrackMetadata()
        guard let items = try? await asset.load(.commonMetadata) else { return meta }

        for item in items {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                if let trimmed = await trimmedString(from: item) {
                    meta.title = trimmed
                }
            case .commonKeyArtist:
                if let trimmed = await trimmedString(from: item) {
                    meta.artist = trimmed
                }
            case .commonKeyAlbumName:
                if let trimmed = await trimmedString(from: item) {
                    meta.albumName = trimmed
                }
            case .commonKeyArtwork:
                if meta.artworkData == nil, let data = try? await item.load(.dataValue) {
                    meta.artworkData = data
                }
            default:
                break
            }
        }

        return meta
    }

    private static func trimmedString(from item: AVMetadataItem) async -> String? {
        guard let value = try? await item.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        try withSecurityScopedAccess(to: sourceURL) {
            if FileManager.default.fileExists(atPath: destinationURL.path()) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func storageFolderURL(for folderName: String) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let libraryURL = applicationSupport.appendingPathComponent("Audiobooks", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        let audiobookFolderURL = libraryURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: audiobookFolderURL, withIntermediateDirectories: true)
        return audiobookFolderURL
    }

    private static func sanitizedFileName(from name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")

        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try await operation()
    }
}
