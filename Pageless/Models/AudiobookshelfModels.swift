import Foundation

nonisolated struct ABSLibrary: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let mediaType: String
}

nonisolated struct ABSLibraryItem: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let libraryId: String
    let mediaType: String
    let media: ABSMedia
    /// Milliseconds since 1970. Drives the "Recently Added" rail.
    var addedAt: Double? = nil

    var addedDate: Date? { addedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

nonisolated struct ABSMedia: Decodable, Equatable, Sendable {
    let metadata: ABSBookMetadata
    let duration: Double?
    let audioTracks: [ABSAudioTrack]?
    let chapters: [ABSChapter]?
    /// `GET /api/items/<id>?expanded=1` returns the playable files as `tracks` (verified on ABS
    /// 2.36.1 — `audioTracks` is null there); a playback session returns `audioTracks`.
    var tracks: [ABSAudioTrack]? = nil
    var coverPath: String? = nil
    var numChapters: Int? = nil
    var numTracks: Int? = nil

    /// Playable files in play order, whichever key the endpoint used.
    var playableTracks: [ABSAudioTrack] {
        let source = (tracks?.isEmpty == false ? tracks : audioTracks) ?? []
        return source.sorted { $0.index < $1.index }
    }

    var hasCover: Bool { !(coverPath ?? "").isEmpty }

    /// Chapter count for display: real chapters when the server knows them, else one per file.
    var chapterCount: Int {
        if let chapters, !chapters.isEmpty { return chapters.count }
        if let numChapters, numChapters > 0 { return numChapters }
        if let numTracks, numTracks > 0 { return numTracks }
        return playableTracks.count
    }
}

nonisolated struct ABSBookMetadata: Decodable, Equatable, Sendable {
    let title: String
    let authorName: String?
    let narratorName: String?
    let description: String?
    var subtitle: String? = nil

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var displayAuthor: String {
        let trimmed = (authorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown author" : trimmed
    }

    /// Nil when the server stores an empty narrator (it sends `""`, not null).
    var displayNarrator: String? {
        let trimmed = (narratorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct ABSAudioTrack: Decodable, Equatable, Sendable {
    let index: Int
    let startOffset: Double?
    let duration: Double
    let title: String
    let contentUrl: String
    let mimeType: String?
    var metaTags: MetaTags? = nil

    nonisolated struct MetaTags: Decodable, Equatable, Sendable {
        var tagTitle: String? = nil
    }

    /// ABS names a track after its file ("chapter-01.mp3"); prefer the embedded title tag and
    /// otherwise drop the extension so the player never shows a filename.
    var displayTitle: String {
        if let tag = metaTags?.tagTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag
        }
        let name = (title as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Track \(index)" : name
    }
}

nonisolated struct ABSChapter: Decodable, Equatable, Sendable {
    let id: Int?
    let start: Double
    let end: Double
    let title: String
}

nonisolated struct ABSPlaybackSession: Decodable, Equatable, Sendable {
    let id: String
    let libraryItemId: String
    let audioTracks: [ABSAudioTrack]
    let chapters: [ABSChapter]?
    let currentTime: Double?
}

nonisolated struct ABSMediaProgress: Decodable, Equatable, Sendable {
    let libraryItemId: String
    let duration: Double
    let progress: Double
    let currentTime: Double
    let isFinished: Bool
    var hideFromContinueListening: Bool? = nil
    /// Milliseconds since 1970.
    var lastUpdate: Double? = nil

    /// Worth a "Continue Listening" card: started, not finished, not hidden by the user.
    var isInProgress: Bool {
        !isFinished && hideFromContinueListening != true && (currentTime > 0 || progress > 0)
    }
}

nonisolated struct ABSProgressUpdate: Encodable, Sendable {
    let duration: Double
    let progress: Double
    let currentTime: Double
    let isFinished: Bool

    init(duration: Double, currentTime: Double, isFinished: Bool) {
        self.duration = duration
        self.progress = isFinished ? 1 : (duration > 0 ? min(max(currentTime / duration, 0), 1) : 0)
        self.currentTime = currentTime
        self.isFinished = isFinished
    }
}

nonisolated struct ABSPage: Decodable, Sendable {
    let results: [ABSLibraryItem]
    let total: Int
    let limit: Int
    let page: Int
}
