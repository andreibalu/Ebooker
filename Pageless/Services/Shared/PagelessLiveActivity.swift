//
//  PagelessLiveActivity.swift
//  Pageless
//
//  ActivityAttributes definition shared between the main app and widget extension.
//

import ActivityKit
import Foundation

struct PagelessPlaybackAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trackTitle: String
        var currentTime: Double
        var duration: Double
        var isPlaying: Bool
        var progress: Double
    }

    var bookTitle: String
    var author: String
    var bookID: String
}
