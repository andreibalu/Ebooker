import Foundation

nonisolated struct ABSLibrary: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let mediaType: String
}

nonisolated struct ABSLibraryItem: Decodable, Equatable, Sendable {
    let id: String
    let libraryId: String
    let mediaType: String
    let media: ABSMedia
}

nonisolated struct ABSMedia: Decodable, Equatable, Sendable {
    let metadata: ABSBookMetadata
    let duration: Double?
    let audioTracks: [ABSAudioTrack]?
    let chapters: [ABSChapter]?
}

nonisolated struct ABSBookMetadata: Decodable, Equatable, Sendable {
    let title: String
    let authorName: String?
    let narratorName: String?
    let description: String?
}

nonisolated struct ABSAudioTrack: Decodable, Equatable, Sendable {
    let index: Int
    let startOffset: Double?
    let duration: Double
    let title: String
    let contentUrl: String
    let mimeType: String?
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
