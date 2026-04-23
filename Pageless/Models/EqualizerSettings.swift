//
//  EqualizerSettings.swift
//  Pageless
//

import Foundation

/// One of five peaking EQ bands applied to audiobook playback.
enum EqualizerBand: Int, CaseIterable, Identifiable {
    case low60
    case lowMid230
    case mid910
    case highMid3600
    case high14k

    var id: Int { rawValue }

    var frequencyHz: Double {
        switch self {
        case .low60: 60
        case .lowMid230: 230
        case .mid910: 910
        case .highMid3600: 3_600
        case .high14k: 14_000
        }
    }

    var shortLabel: String {
        switch self {
        case .low60: "60"
        case .lowMid230: "230"
        case .mid910: "910"
        case .highMid3600: "3.6k"
        case .high14k: "14k"
        }
    }
}

/// Preset tonal curves. `.custom` is selected when the user edits any band manually.
enum EqualizerPreset: String, CaseIterable, Identifiable, Codable {
    case flat
    case voiceBoost
    case bassBoost
    case trebleBoost
    case podcast
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: "Flat"
        case .voiceBoost: "Voice Boost"
        case .bassBoost: "Bass Boost"
        case .trebleBoost: "Treble Boost"
        case .podcast: "Podcast"
        case .custom: "Custom"
        }
    }

    /// Gains per band in the `EqualizerBand.allCases` order (dB). `.custom` returns flat as a fallback.
    var bandGainsDB: [Double] {
        switch self {
        case .flat:         return [0, 0, 0, 0, 0]
        case .voiceBoost:   return [-2, 0, 4, 5, 1]
        case .bassBoost:    return [6, 4, 0, -1, -1]
        case .trebleBoost:  return [-2, -1, 0, 3, 5]
        case .podcast:      return [-3, 1, 3, 4, 2]
        case .custom:       return [0, 0, 0, 0, 0]
        }
    }
}

/// Persisted configuration snapshot for per-book EQ. Encoded to JSON in Audiobook storage.
struct EqualizerConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var preset: EqualizerPreset
    var preampDB: Double
    var bandGainsDB: [Double]

    static let preampRange: ClosedRange<Double> = 0...12
    static let bandRange: ClosedRange<Double> = -12...12

    static let flat = EqualizerConfiguration(
        isEnabled: false,
        preset: .flat,
        preampDB: 0,
        bandGainsDB: [0, 0, 0, 0, 0]
    )

    /// Clamps preamp/band gains to their legal ranges and normalizes band count to 5.
    mutating func clamp() {
        preampDB = min(max(preampDB, Self.preampRange.lowerBound), Self.preampRange.upperBound)
        let clamped = bandGainsDB.map {
            min(max($0, Self.bandRange.lowerBound), Self.bandRange.upperBound)
        }
        if clamped.count == EqualizerBand.allCases.count {
            bandGainsDB = clamped
        } else if clamped.count < EqualizerBand.allCases.count {
            bandGainsDB = clamped + Array(repeating: 0.0, count: EqualizerBand.allCases.count - clamped.count)
        } else {
            bandGainsDB = Array(clamped.prefix(EqualizerBand.allCases.count))
        }
    }

    /// Creates a clamped copy using the preset's gains.
    static func preset(_ preset: EqualizerPreset, preampDB: Double, isEnabled: Bool) -> EqualizerConfiguration {
        var config = EqualizerConfiguration(
            isEnabled: isEnabled,
            preset: preset,
            preampDB: preampDB,
            bandGainsDB: preset.bandGainsDB
        )
        config.clamp()
        return config
    }
}

/// JSON codec helpers used by `Audiobook` backing fields.
enum EqualizerConfigurationCodec {
    static func encode(_ configuration: EqualizerConfiguration) -> String? {
        guard let data = try? JSONEncoder().encode(configuration) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> EqualizerConfiguration? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        guard var config = try? JSONDecoder().decode(EqualizerConfiguration.self, from: data) else { return nil }
        config.clamp()
        return config
    }
}
