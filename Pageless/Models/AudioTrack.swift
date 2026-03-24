//
//  AudioTrack.swift
//  Pageless
//

import Foundation
import SwiftData

@Model
final class AudioTrack: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalFileName: String
    var storedFileName: String
    var orderIndex: Int
    var duration: Double
    var audiobook: Audiobook?

    init(
        title: String,
        originalFileName: String,
        storedFileName: String,
        orderIndex: Int,
        duration: Double,
        audiobook: Audiobook? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.orderIndex = orderIndex
        self.duration = duration
        self.audiobook = audiobook
    }
}
