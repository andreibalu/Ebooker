//
//  Moment.swift
//  Ebooker
//

import Foundation
import SwiftData

@Model
final class Moment {
    @Attribute(.unique) var id: UUID
    var trackIndex: Int
    var time: Double
    var label: String
    var createdAt: Date
    var audiobook: Audiobook?

    init(trackIndex: Int, time: Double, label: String, audiobook: Audiobook) {
        self.id = UUID()
        self.trackIndex = trackIndex
        self.time = time
        self.label = label
        self.createdAt = .now
        self.audiobook = audiobook
    }
}
