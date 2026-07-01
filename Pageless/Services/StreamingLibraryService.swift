//
//  StreamingLibraryService.swift
//  Pageless
//

import Foundation
import SwiftData

enum StreamingLibraryService {
    /// Creates a streaming Audiobook entry from cached LibriVox track data.
    /// No files are downloaded — tracks store remote URLs for on-demand streaming.
    static func addToLibrary(
        book: LibriVoxBook,
        tracks: [CachedLibriVoxTrack],
        modelContext: ModelContext
    ) async throws -> Audiobook {
        if let match = try FreeBookIdentityService.match(
            catalogId: book.id,
            modelContext: modelContext
        ) {
            if match.classification == .archived {
                match.audiobook.isArchived = false
                match.audiobook.isDownloaded = false
                try modelContext.save()
            }
            return match.audiobook
        }

        // LibriVox cover URLs are unreliable — skip the fetch and let the
        // generated letter template render in every cover surface instead.
        let folderName = UUID().uuidString

        let totalDuration = tracks.reduce(0.0) { $0 + $1.durationSeconds }

        let audiobook = Audiobook(
            title: book.title,
            author: book.authorDisplay,
            folderName: folderName,
            coverArtData: nil,
            totalDuration: totalDuration,
            isFreeBook: true,
            catalogId: book.id,
            isDownloaded: false
        )

        modelContext.insert(audiobook)

        for track in tracks {
            let safeTitle = track.title.isEmpty ? "Track \(track.orderIndex + 1)" : track.title
            let audioTrack = AudioTrack(
                title: safeTitle,
                originalFileName: URL(string: track.listenURL)?.lastPathComponent ?? "",
                storedFileName: "",
                orderIndex: track.orderIndex,
                duration: track.durationSeconds
            )
            audioTrack.remoteURLString = track.listenURL
            audioTrack.audiobook = audiobook
            modelContext.insert(audioTrack)
            audiobook.tracks.append(audioTrack)
        }

        try modelContext.save()
        return audiobook
    }
}
