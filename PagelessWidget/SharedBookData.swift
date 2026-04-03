//
//  SharedBookData.swift
//  Pageless
//
//  Lightweight Codable snapshot shared between the main app and widget extension
//  via App Group UserDefaults.
//

import Foundation

struct SharedBookData: Codable, Identifiable {
    var id: String
    var title: String
    var author: String
    var coverArtData: Data?
    var progress: Double
    var currentTrackTitle: String
    var totalDuration: Double
    var listenedDuration: Double
    var lastPlayedAt: Date?
    var isFavorite: Bool
}

struct SharedNowPlayingData: Codable {
    var bookID: String
    var title: String
    var author: String
    var coverArtData: Data?
    var trackTitle: String
    var currentTime: Double
    var duration: Double
    var isPlaying: Bool
    var playbackRate: Double
    var progress: Double
}
