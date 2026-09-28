//
//  AudiobookshelfLibraryService.swift
//  Pageless
//

import Foundation
import SwiftData

/// Turns an Audiobookshelf library item into an Unpaged streaming `Audiobook`, and maps positions
/// between Unpaged's (track, time-in-track) pair and ABS's single book-global `currentTime`.
///
/// Invariant: every URL written here is token-less. The credential is appended only at play time
/// (`AudiobookshelfClient.playbackURL(forStoredURL:)`), because `Audiobook`/`AudioTrack` rows sync
/// to the user's iCloud.
enum AudiobookshelfLibraryService {
    /// The existing row for an ABS item, so adding the same item twice reuses it.
    static func existingBook(itemID: String, modelContext: ModelContext) throws -> Audiobook? {
        try modelContext.fetch(FetchDescriptor<Audiobook>()).first { $0.absItemID == itemID }
    }

    /// Adds (or returns the existing row for) an expanded ABS item as a streaming book.
    /// - Parameters:
    ///   - trackURLs: token-less absolute URLs, one per `item.media.playableTracks` entry, from
    ///     `AudiobookshelfClient.storedStreamURL(for:)`.
    ///   - progress: server progress; when present and the book is new, seeds the start position.
    @discardableResult
    static func addToLibrary(
        item: ABSLibraryItem,
        trackURLs: [URL],
        progress: ABSMediaProgress?,
        coverArtData: Data?,
        modelContext: ModelContext
    ) throws -> Audiobook {
        if let existing = try existingBook(itemID: item.id, modelContext: modelContext) {
            if existing.coverArtData == nil, let coverArtData { existing.coverArtData = coverArtData }
            try modelContext.save()
            return existing
        }

        let tracks = item.media.playableTracks
        guard !tracks.isEmpty, tracks.count == trackURLs.count else {
            throw AudiobookshelfError.invalidMediaURL
        }
        for url in trackURLs where containsCredential(url) {
            throw AudiobookshelfError.invalidMediaURL
        }

        let metadata = item.media.metadata
        let durations = tracks.map { max($0.duration, 0) }
        let total = item.media.duration.flatMap { $0 > 0 ? $0 : nil } ?? durations.reduce(0, +)

        let audiobook = Audiobook(
            title: metadata.displayTitle,
            author: (metadata.authorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            folderName: UUID().uuidString,
            coverArtData: coverArtData,
            totalDuration: total,
            absItemID: item.id,
            isDownloaded: false
        )
        modelContext.insert(audiobook)

        let titles = trackTitles(tracks: tracks, chapters: item.media.chapters ?? [])
        for (offset, pair) in zip(tracks, trackURLs).enumerated() {
            let (track, url) = pair
            let audioTrack = AudioTrack(
                title: titles[offset],
                originalFileName: track.title,
                storedFileName: "",
                orderIndex: offset,
                duration: track.duration
            )
            audioTrack.remoteURLString = url.absoluteString
            audioTrack.audiobook = audiobook
            modelContext.insert(audioTrack)
            audiobook.tracks.append(audioTrack)
        }

        if let progress {
            if progress.isFinished {
                audiobook.isFinished = true
            } else if progress.currentTime > 0 {
                let position = position(forGlobalTime: progress.currentTime, trackDurations: durations)
                audiobook.currentTrackIndex = position.trackIndex
                audiobook.currentTime = position.timeInTrack
                audiobook.progressTrackIndex = position.trackIndex
                audiobook.progressTime = position.timeInTrack
                audiobook.progressUpdatedAt = .now
            }
        }

        try modelContext.save()
        return audiobook
    }

    // MARK: - Track titles

    /// Listener-facing titles for an item's playable tracks, taken from the book's chapter metadata
    /// when it maps onto the files: one chapter per file (same count), or a chapter that starts
    /// where the file starts. Anything unmapped falls back to the file's title tag, then its name
    /// without the extension (`ABSAudioTrack.displayTitle`).
    static func trackTitles(tracks: [ABSAudioTrack], chapters: [ABSChapter]) -> [String] {
        let usable = chapters
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        if !usable.isEmpty, usable.count == tracks.count {
            return usable.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        var start = 0.0
        return tracks.map { track in
            let trackStart = track.startOffset ?? start
            start = trackStart + max(track.duration, 0)
            if let chapter = usable.first(where: { abs($0.start - trackStart) < 1.5 }) {
                return chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return track.displayTitle
        }
    }

    // MARK: - Position mapping

    static func globalTime(trackIndex: Int, timeInTrack: Double, trackDurations: [Double]) -> Double {
        let before = trackDurations.prefix(max(0, min(trackIndex, trackDurations.count))).reduce(0, +)
        return max(0, before + max(timeInTrack, 0))
    }

    static func position(forGlobalTime time: Double, trackDurations: [Double]) -> (trackIndex: Int, timeInTrack: Double) {
        guard !trackDurations.isEmpty else { return (0, 0) }
        var remaining = max(time, 0)
        for (index, duration) in trackDurations.enumerated() {
            if remaining < duration || index == trackDurations.count - 1 {
                return (index, min(remaining, max(duration, 0)))
            }
            remaining -= duration
        }
        return (trackDurations.count - 1, 0)
    }

    static func progressSnapshot(
        for audiobook: Audiobook,
        trackIndex: Int,
        timeInTrack: Double,
        isFinished: Bool
    ) -> ABSProgressSnapshot? {
        guard let itemID = audiobook.absItemID, !itemID.isEmpty else { return nil }
        let durations = audiobook.sortedTracks.map(\.duration)
        let total = audiobook.totalDuration > 0 ? audiobook.totalDuration : durations.reduce(0, +)
        guard total > 0 else { return nil }
        let current = isFinished ? total : min(globalTime(trackIndex: trackIndex, timeInTrack: timeInTrack,
                                                           trackDurations: durations), total)
        return ABSProgressSnapshot(itemID: itemID, currentTime: current, duration: total, isFinished: isFinished)
    }

    /// True when a URL carries anything that looks like a credential. Used as a last-line guard
    /// before a URL is written to a synced row.
    static func containsCredential(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { ["token", "api_key", "apikey", "access_token"].contains($0.name.lowercased()) }
    }
}
