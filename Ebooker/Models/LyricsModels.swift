//
//  LyricsModels.swift
//  Ebooker
//

import Foundation

struct LyricsSegment: Codable, Identifiable {
    let id: Int
    let text: String
    let start: Double   // seconds, track-relative
    let end: Double
}

struct TrackLyrics: Codable {
    let trackID: String
    let modelName: String
    let createdAt: Date
    let segments: [LyricsSegment]
}

enum WhisperModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case failed(String)
}

enum LyricsStatus: Equatable {
    case modelNotReady
    case transcribing(Double)   // progress 0.0...1.0
    case ready
    case failed(String)
}
