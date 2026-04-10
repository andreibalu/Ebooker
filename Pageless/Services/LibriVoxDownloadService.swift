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

    /// Downloads all tracks, fetches cover art, and imports the book into the SwiftData library.
    /// Returns the newly created Audiobook so the caller can navigate to it.
    static func downloadAndImport(
        book: LibriVoxBook,
        tracks: [LibriVoxAPITrack],
        modelContext: ModelContext,
        onProgress: @escaping ProgressHandler
    ) async throws -> Audiobook {
        let folderName = UUID().uuidString
        let folderURL = try makeStorageFolder(named: folderName)

        do {
            // Cover art (best-effort — nil is fine)
            let coverData = await fetchCoverArt(url: book.bestCoverURL)

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

                let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
                // Move from temp location (URLSession cleans up temp automatically on move)
                if FileManager.default.fileExists(atPath: destURL.path()) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                audioTracks.append(AudioTrack(
                    title: safeTitle,
                    originalFileName: remoteURL.lastPathComponent,
                    storedFileName: storedFileName,
                    orderIndex: index,
                    duration: track.durationSeconds
                ))

                onProgress(index + 1, tracks.count)
            }

            // Build Audiobook
            let totalDuration = audioTracks.reduce(0) { $0 + $1.duration }
            let audiobook = Audiobook(
                title: book.title,
                author: book.authorDisplay,
                folderName: folderName,
                coverArtData: coverData,
                totalDuration: totalDuration
            )

            modelContext.insert(audiobook)
            for track in audioTracks {
                track.audiobook = audiobook
                modelContext.insert(track)
                audiobook.tracks.append(track)
            }
            try modelContext.save()

            return audiobook

        } catch {
            // Clean up partial download folder on failure
            try? FileManager.default.removeItem(at: folderURL)
            throw error
        }
    }

    // MARK: - Private helpers

    private static func fetchCoverArt(url: URL?) async -> Data? {
        guard let url else { return nil }
        return try? await URLSession.shared.data(from: url).0
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
