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

    // High-water mark: the furthest point the user has reached through listening.
    // Nullable for lightweight migration (same pattern as _isFavorite).
    private var _progressTrackIndex: Int?
    private var _progressTime: Double?
    private var _progressUpdatedAt: Date?

    var progressTrackIndex: Int? { get { _progressTrackIndex } set { _progressTrackIndex = newValue } }
    var progressTime: Double? { get { _progressTime } set { _progressTime = newValue } }
    var progressUpdatedAt: Date? { get { _progressUpdatedAt } set { _progressUpdatedAt = newValue } }
    var hasProgressPosition: Bool { _progressTrackIndex != nil && _progressTime != nil }

    // Smart summary persisted until the progress marker moves (nullable for lightweight migration).
    private var _progressRecapText: String?
    private var _progressRecapHeadline: String?
    private var _progressRecapAnchorTrackIndex: Int?
    private var _progressRecapAnchorTime: Double?

    var progressRecapText: String? {
        get { _progressRecapText }
        set { _progressRecapText = newValue }
    }

    var progressRecapHeadline: String? {
        get { _progressRecapHeadline }
        set { _progressRecapHeadline = newValue }
    }

    var progressRecapAnchorTrackIndex: Int? {
        get { _progressRecapAnchorTrackIndex }
        set { _progressRecapAnchorTrackIndex = newValue }
    }

    var progressRecapAnchorTime: Double? {
        get { _progressRecapAnchorTime }
        set { _progressRecapAnchorTime = newValue }
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

    var progressListenedDuration: Double {
        guard let trackIdx = progressTrackIndex, let time = progressTime else { return 0 }
        let completed = sortedTracks
            .filter { $0.orderIndex < trackIdx }
            .reduce(0) { $0 + $1.duration }
        return min(completed + time, totalDuration)
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

    /// Deduplicated, case-insensitive, first-seen order list of character names from all moments.
    var castList: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for moment in moments {
            for character in moment.characters {
                let key = character.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(character)
                }
            }
        }
        return result
    }

    // MARK: - Progress recap (smart summary)

    /// Removes any persisted recap/headline and anchor.
    func clearProgressRecap() {
        _progressRecapText = nil
        _progressRecapHeadline = nil
        _progressRecapAnchorTrackIndex = nil
        _progressRecapAnchorTime = nil
    }

    /// Stores recap output tied to the progress position it was generated for (sorted track index + time).
    func storeProgressRecap(text: String, headline: String?, anchorTrackIndex: Int, anchorTime: Double) {
        _progressRecapText = text
        _progressRecapHeadline = headline
        _progressRecapAnchorTrackIndex = anchorTrackIndex
        _progressRecapAnchorTime = anchorTime
    }

    /// Drops persisted recap if it no longer matches the current high-water progress marker.
    func discardProgressRecapIfAnchorMismatched() {
        guard _progressRecapText != nil else { return }
        guard let pt = _progressTrackIndex, let ptm = _progressTime else {
            clearProgressRecap()
            return
        }
        guard let at = _progressRecapAnchorTrackIndex, let atm = _progressRecapAnchorTime else {
            clearProgressRecap()
            return
        }
        if pt != at || ptm != atm {
            clearProgressRecap()
        }
    }
}
