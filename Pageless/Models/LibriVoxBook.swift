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

    init(
        id: String,
        title: String,
        authorDisplay: String,
        bookDescription: String,
        language: String,
        totalTimeSecs: Int,
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
    }

    var formattedDuration: String {
        guard totalTimeSecs > 0 else { return "Unknown length" }
        return TimeFormatter.durationSummary(seconds: Double(totalTimeSecs))
    }

    var coverThumbnailURL: URL? {
        guard let s = coverThumbnailURLString, !s.isEmpty else { return nil }
        return URL(string: s)
    }
}
