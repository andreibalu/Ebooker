//
//  MomentEnums.swift
//  Pageless
//

import Foundation

enum MomentCategory: String, CaseIterable, Identifiable, Codable {
    case dialogue, action, plotTwist, characterIntro, worldBuilding
    case quote, reflection, humor, tension, romance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dialogue: "Dialogue"
        case .action: "Action"
        case .plotTwist: "Plot Twist"
        case .characterIntro: "Character Intro"
        case .worldBuilding: "World Building"
        case .quote: "Quote"
        case .reflection: "Reflection"
        case .humor: "Humor"
        case .tension: "Tension"
        case .romance: "Romance"
        }
    }
}

enum MomentMood: String, CaseIterable, Identifiable, Codable {
    case tense, funny, sad, romantic, inspirational, mysterious, peaceful, dramatic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tense: "Tense"
        case .funny: "Funny"
        case .sad: "Sad"
        case .romantic: "Romantic"
        case .inspirational: "Inspirational"
        case .mysterious: "Mysterious"
        case .peaceful: "Peaceful"
        case .dramatic: "Dramatic"
        }
    }
}
