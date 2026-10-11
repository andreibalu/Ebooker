//
//  EqualizerSettingsTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct EqualizerSettingsTests {
    @Test func configurationClampsPreampToLegalRange() {
        var config = EqualizerConfiguration(
            isEnabled: true,
            preset: .custom,
            preampDB: 99,
            bandGainsDB: [0, 0, 0, 0, 0]
        )
        config.clamp()
        #expect(config.preampDB == EqualizerConfiguration.preampRange.upperBound)

        var negative = EqualizerConfiguration(
            isEnabled: true,
            preset: .custom,
            preampDB: -50,
            bandGainsDB: [0, 0, 0, 0, 0]
        )
        negative.clamp()
        #expect(negative.preampDB == EqualizerConfiguration.preampRange.lowerBound)
    }

    @Test func configurationClampsBandGainsToLegalRange() {
        var config = EqualizerConfiguration(
            isEnabled: true,
            preset: .custom,
            preampDB: 0,
            bandGainsDB: [99, -99, 5, 12, -12]
        )
        config.clamp()
        #expect(config.bandGainsDB[0] == 12)
        #expect(config.bandGainsDB[1] == -12)
        #expect(config.bandGainsDB[2] == 5)
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

    @Test func codecReturnsNilForInvalidJSON() {
        #expect(EqualizerConfigurationCodec.decode(nil) == nil)
        #expect(EqualizerConfigurationCodec.decode("not json") == nil)
    }
}
