//
//  DownloadActivityAttributes.swift
//  Pageless
//

import ActivityKit
import Foundation

struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let activeBookCount: Int
        let completedTracks: Int
        let totalTracks: Int
        let progress: Double
        let phase: DownloadActivityPhase
        let failureMessage: String?
    }

    let startedAt: Date
}

enum DownloadActivityPhase: String, Codable, Hashable, Sendable {
    case preparing
    case downloading
    case failed
    case complete
}

struct DownloadActivitySnapshot: Equatable, Sendable {
    let title: String
    let activeBookCount: Int
    let completedTracks: Int
    let totalTracks: Int
    let progress: Double
    let phase: DownloadActivityPhase
    let failureMessage: String?

    var contentState: DownloadActivityAttributes.ContentState {
        .init(
            title: title,
            activeBookCount: activeBookCount,
            completedTracks: completedTracks,
            totalTracks: totalTracks,
            progress: min(1, max(0, progress)),
            phase: phase,
            failureMessage: failureMessage
        )
    }

}
