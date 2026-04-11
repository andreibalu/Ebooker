//
//  LibriVoxBook.swift
//  Pageless
//

import Foundation
import SwiftData

@Model
final class LibriVoxBook {
    @Attribute(.unique) var id: String
    var title: String
    var authorDisplay: String
    var bookDescription: String
    var language: String
    var totalTimeSecs: Int
    var coverThumbnailURLString: String?
    var librivoxURLString: String?
    var internetArchiveURLString: String?
    var rssURLString: String?
    var lastSyncedAt: Date

    // Schema-migration-safe genres field (private backing, JSON-encoded [String])
    private var _genresRaw: String?

    // Cached track data for offline "Add to Library" (JSON-encoded [CachedLibriVoxTrack])
    private var _cachedTracksRaw: String?

    var genres: [String] {
        get {
            guard let raw = _genresRaw,
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard !newValue.isEmpty,
                  let data = try? JSONEncoder().encode(newValue),
                  let str = String(data: data, encoding: .utf8)
            else { _genresRaw = nil; return }
            _genresRaw = str
        }
    }

    var cachedTracks: [CachedLibriVoxTrack]? {
        get {
            guard let raw = _cachedTracksRaw,
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([CachedLibriVoxTrack].self, from: data)
            else { return nil }
            return decoded
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let str = String(data: data, encoding: .utf8)
            else { _cachedTracksRaw = nil; return }
            _cachedTracksRaw = str
        }
    }

    init(
        id: String,
        title: String,
        authorDisplay: String,
        bookDescription: String,
        language: String,
        totalTimeSecs: Int,
        genres: [String] = [],
        coverThumbnailURLString: String? = nil,
        librivoxURLString: String? = nil,
        internetArchiveURLString: String? = nil,
        rssURLString: String? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.authorDisplay = authorDisplay
        self.bookDescription = bookDescription
        self.language = language
        self.totalTimeSecs = totalTimeSecs
        self.coverThumbnailURLString = coverThumbnailURLString
        self.librivoxURLString = librivoxURLString
        self.internetArchiveURLString = internetArchiveURLString
        self.rssURLString = rssURLString
        self.lastSyncedAt = lastSyncedAt
        if !genres.isEmpty,
           let data = try? JSONEncoder().encode(genres),
           let str = String(data: data, encoding: .utf8) {
            _genresRaw = str
        } else {
            _genresRaw = nil
        }
    }

    var formattedDuration: String {
        guard totalTimeSecs > 0 else { return "Unknown length" }
        return TimeFormatter.durationSummary(seconds: Double(totalTimeSecs))
    }

    var coverThumbnailURL: URL? {
        guard let s = coverThumbnailURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Identifier extracted from the Internet Archive details URL (last path component).
    private var internetArchiveIdentifier: String? {
        guard let s = internetArchiveURLString,
              let url = URL(string: s) else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty ? nil : id
    }

    /// Best available cover image URL: LibriVox thumbnail first, then Internet Archive services image.
    var bestCoverURL: URL? {
        if let s = coverThumbnailURLString, !s.isEmpty, let url = URL(string: s) { return url }
        if let id = internetArchiveIdentifier {
            return URL(string: "https://archive.org/services/img/\(id)")
        }
        return nil
    }
}
