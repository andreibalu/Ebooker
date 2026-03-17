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
    var transcript: String?
    var aiGeneratedName: Bool
    var notes: String?

    init(trackIndex: Int, time: Double, label: String, audiobook: Audiobook, transcript: String? = nil, aiGeneratedName: Bool = false, notes: String? = nil) {
        self.id = UUID()
        self.trackIndex = trackIndex
        self.time = time
        self.label = label
        self.createdAt = .now
        self.audiobook = audiobook
        self.transcript = transcript
        self.aiGeneratedName = aiGeneratedName
        self.notes = notes
    }
}
