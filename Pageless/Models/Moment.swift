//
//  Moment.swift
//  Pageless
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
    var isPinned: Bool = false

    // Nullable backing fields for lightweight migration
    private var _categoriesRaw: String?
    private var _quoteLine: String?
    private var _charactersRaw: String?
    private var _moodRaw: String?

    var categories: [MomentCategory] {
        get {
            guard let raw = _categoriesRaw,
                  let data = raw.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings.compactMap { MomentCategory(rawValue: $0) }
        }
        set {
            let strings = newValue.map(\.rawValue)
            _categoriesRaw = (try? String(data: JSONEncoder().encode(strings), encoding: .utf8)) ?? nil
        }
    }

    var quoteLine: String? {
        get { _quoteLine }
        set { _quoteLine = newValue }
    }

    var characters: [String] {
        get {
            guard let raw = _charactersRaw,
                  let data = raw.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings
        }
        set {
            _charactersRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? nil
        }
    }

    var mood: MomentMood? {
        get { _moodRaw.flatMap { MomentMood(rawValue: $0) } }
        set { _moodRaw = newValue?.rawValue }
    }

    init(
        trackIndex: Int,
        time: Double,
        label: String,
        audiobook: Audiobook,
        transcript: String? = nil,
        aiGeneratedName: Bool = false,
        notes: String? = nil,
        categories: [MomentCategory] = [],
        quoteLine: String? = nil,
        characters: [String] = [],
        mood: MomentMood? = nil,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.trackIndex = trackIndex
        self.time = time
        self.label = label
        self.createdAt = .now
        self.audiobook = audiobook
        self.transcript = transcript
        self.aiGeneratedName = aiGeneratedName
        self.notes = notes
        self.isPinned = isPinned
        self.categories = categories
        self.quoteLine = quoteLine
        self.characters = characters
        self.mood = mood
    }
}
