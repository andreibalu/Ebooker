//
//  EqualizerSettingsTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct EqualizerSettingsTests {

    @Test func presetsShapeTheFiveAscendingBands() {
        let freqs = EqualizerBand.allCases.map(\.frequencyHz)
        #expect(freqs == freqs.sorted())
        for preset in EqualizerPreset.allCases {
            #expect(preset.bandGainsDB.count == EqualizerBand.allCases.count)
        }

        let voice = EqualizerPreset.voiceBoost.bandGainsDB
        #expect(voice[EqualizerBand.mid910.rawValue] > 0)
        #expect(voice[EqualizerBand.highMid3600.rawValue] > 0)
        let bass = EqualizerPreset.bassBoost.bandGainsDB
        #expect(bass[EqualizerBand.low60.rawValue] > 0)
        #expect(bass[EqualizerBand.high14k.rawValue] <= 0)
        #expect(EqualizerPreset.trebleBoost.bandGainsDB[EqualizerBand.high14k.rawValue] > 0)
    }

    @Test func configurationNormalizesBandCountTo5() {
        var shortConfig = EqualizerConfiguration(
            isEnabled: true,
            preset: .custom,
            preampDB: 0,
            bandGainsDB: [1, 2]
        )
        shortConfig.clamp()
        #expect(shortConfig.bandGainsDB.count == EqualizerBand.allCases.count)

        var longConfig = EqualizerConfiguration(
            isEnabled: true,
            preset: .custom,
            preampDB: 0,
            bandGainsDB: [1, 2, 3, 4, 5, 6, 7, 8]
        )
        longConfig.clamp()
        #expect(longConfig.bandGainsDB.count == EqualizerBand.allCases.count)
    }

    @Test func configurationRoundTripsThroughCodec() {
        let original = EqualizerConfiguration(
            isEnabled: true,
            preset: .voiceBoost,
            preampDB: 6,
            bandGainsDB: [-2, 0, 4, 5, 1]
        )
        let json = EqualizerConfigurationCodec.encode(original)
        #expect(json != nil)
        let decoded = EqualizerConfigurationCodec.decode(json)
        #expect(decoded == original)
    }

    @Test func codecReturnsNilForInvalidJSON() {
        #expect(EqualizerConfigurationCodec.decode(nil) == nil)
        #expect(EqualizerConfigurationCodec.decode("not json") == nil)
    }

    @Test func presetFactoryClamps() {
        let config = EqualizerConfiguration.preset(.bassBoost, preampDB: 99, isEnabled: true)
        #expect(config.preampDB == EqualizerConfiguration.preampRange.upperBound)
        #expect(config.preset == .bassBoost)
        #expect(config.bandGainsDB == EqualizerPreset.bassBoost.bandGainsDB)
    }
}
