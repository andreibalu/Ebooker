//
//  Audiobook.swift
//  Ebooker
//

import Foundation
import SwiftData

@Model
final class Audiobook: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var folderName: String
    @Attribute(.externalStorage) var coverArtData: Data?
    var createdAt: Date
    var lastPlayedAt: Date?
    var totalDuration: Double
    var currentTrackIndex: Int
    var currentTime: Double
    var playbackRate: Double
    var isFinished: Bool

    // Stored as Bool? so CoreData can add this column as NULL for existing rows
    // during automatic lightweight migration. The computed wrapper below keeps
    // the public API non-optional everywhere else in the codebase.
    private var _isFavorite: Bool?

    var isFavorite: Bool {
        get { _isFavorite ?? false }
        set { _isFavorite = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \AudioTrack.audiobook)
    var tracks: [AudioTrack]

    @Relationship(deleteRule: .cascade, inverse: \Moment.audiobook)
    var moments: [Moment] = []

    init(
        title: String,
        author: String = "",
        folderName: String,
        coverArtData: Data? = nil,
        createdAt: Date = .now,
        lastPlayedAt: Date? = nil,
        totalDuration: Double = 0,
        currentTrackIndex: Int = 0,
        currentTime: Double = 0,
        playbackRate: Double = 1,
        isFinished: Bool = false,
        isFavorite: Bool = false,
        tracks: [AudioTrack] = []
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.folderName = folderName
        self.coverArtData = coverArtData
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
        self.totalDuration = totalDuration
        self.currentTrackIndex = currentTrackIndex
        self.currentTime = currentTime
        self.playbackRate = playbackRate
        self.isFinished = isFinished
        self._isFavorite = isFavorite
        self.tracks = tracks
    }

    var sortedTracks: [AudioTrack] {
        tracks.sorted { $0.orderIndex < $1.orderIndex }
    }

    var listenedDuration: Double {
        guard !sortedTracks.isEmpty else { return 0 }

        let completed = sortedTracks
            .filter { $0.orderIndex < currentTrackIndex }
            .reduce(0) { $0 + $1.duration }

        return min(completed + currentTime, totalDuration)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return listenedDuration / totalDuration
    }

    var remainingDuration: Double {
        max(totalDuration - listenedDuration, 0)
    }

    var currentTrackTitle: String {
        guard sortedTracks.indices.contains(currentTrackIndex) else { return "Ready to play" }
        return sortedTracks[currentTrackIndex].title
    }

    var displayAuthor: String {
        author.isEmpty ? "Unknown author" : author
    }
}
