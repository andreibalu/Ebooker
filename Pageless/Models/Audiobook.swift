//
//  Audiobook.swift
//  Pageless
//

import Foundation
import SwiftData

@Model
final class Audiobook: Identifiable {
    // CloudKit-backed SwiftData stores cannot declare @Attribute(.unique);
    // app-level UUID uniqueness is enforced by `id` semantics.
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var folderName: String = ""
    @Attribute(.externalStorage) var coverArtData: Data?
    var createdAt: Date = Date.distantPast
    var lastPlayedAt: Date?
    var totalDuration: Double = 0
    var currentTrackIndex: Int = 0
    var currentTime: Double = 0
    var playbackRate: Double = 1
    var isFinished: Bool = false

    // Set the first time this row is observed locally; used to sort orphan books
    // in the Cloud Library picker so the most-recently-synced appear first.
    private var _iCloudRecordCreatedAt: Date?
    var iCloudRecordCreatedAt: Date? {
        get { _iCloudRecordCreatedAt }
        set { _iCloudRecordCreatedAt = newValue }
    }

    // Stored as Bool? so CoreData can add this column as NULL for existing rows
    // during automatic lightweight migration. The computed wrapper below keeps
    // the public API non-optional everywhere else in the codebase.
    private var _isFavorite: Bool?

    // Nullable for lightweight migration (same pattern as _isFavorite).
    private var _isFreeBook: Bool?
    private var _catalogId: String?

    // Nullable for lightweight migration. Defaults to true so existing books (all local) are correct.
    private var _isDownloaded: Bool?

    var isFreeBook: Bool {
        get { _isFreeBook ?? false }
        set { _isFreeBook = newValue }
    }

    var catalogId: String? {
        get { _catalogId }
        set { _catalogId = newValue }
    }

    var isDownloaded: Bool {
        get { _isDownloaded ?? true }
        set { _isDownloaded = newValue }
    }

    // Own books that synced from iCloud but lack local files have isDownloaded==false too —
    // isFreeBook distinguishes them from genuinely streaming LibriVox entries.
    var isStreamingOnly: Bool { !isDownloaded && isFreeBook }

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

    // Per-book equalizer + amplifier state. Nullable for lightweight migration.
    // `_eqBandGainsJSON` stores a JSON array of 5 Doubles representing dB gains.
    private var _eqEnabled: Bool?
    private var _eqPreampDB: Double?
    private var _eqPresetRaw: String?
    private var _eqBandGainsJSON: String?

    var equalizerConfiguration: EqualizerConfiguration {
        get {
            let enabled = _eqEnabled ?? false
            let preamp = _eqPreampDB ?? 0
            let preset = EqualizerPreset(rawValue: _eqPresetRaw ?? "") ?? .flat
            let bands = decodeBandGains(_eqBandGainsJSON) ?? preset.bandGainsDB
            var config = EqualizerConfiguration(
                isEnabled: enabled,
                preset: preset,
                preampDB: preamp,
                bandGainsDB: bands
            )
            config.clamp()
            return config
        }
        set {
            var clamped = newValue
            clamped.clamp()
            _eqEnabled = clamped.isEnabled
            _eqPreampDB = clamped.preampDB
            _eqPresetRaw = clamped.preset.rawValue
            _eqBandGainsJSON = encodeBandGains(clamped.bandGainsDB)
        }
    }

    private func decodeBandGains(_ json: String?) -> [Double]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        guard let array = try? JSONDecoder().decode([Double].self, from: data) else { return nil }
        return array.count == EqualizerBand.allCases.count ? array : nil
    }

    private func encodeBandGains(_ gains: [Double]) -> String? {
        guard let data = try? JSONEncoder().encode(gains) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // CloudKit requires to-many relationships to be optional. We keep the public API
    // non-optional via computed wrappers so existing callsites don't have to change.
    // `originalName` preserves data from the pre-iCloud store where these were named `tracks`/`moments`.
    @Relationship(deleteRule: .cascade, originalName: "tracks", inverse: \AudioTrack.audiobook)
    private var _tracks: [AudioTrack]? = []

    @Relationship(deleteRule: .cascade, originalName: "moments", inverse: \Moment.audiobook)
    private var _moments: [Moment]? = []

    var tracks: [AudioTrack] {
        get { _tracks ?? [] }
        set { _tracks = newValue }
    }

    var moments: [Moment] {
        get { _moments ?? [] }
        set { _moments = newValue }
    }

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
        isFreeBook: Bool = false,
        catalogId: String? = nil,
        isDownloaded: Bool = true,
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
        self._isFreeBook = isFreeBook
        self._catalogId = catalogId
        self._isDownloaded = isDownloaded
        self._tracks = tracks
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
