//
//  AudiobookEqualizerTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct AudiobookEqualizerTests {
    @Test func defaultConfigurationIsFlatAndDisabled() {
        let book = Audiobook(title: "Test", folderName: "test")
        let config = book.equalizerConfiguration
        #expect(config.isEnabled == false)
        #expect(config.preset == .flat)
        #expect(config.preampDB == 0)
        #expect(config.bandGainsDB == EqualizerPreset.flat.bandGainsDB)
    }

    @Test func settingConfigurationClampsOutOfRangeValues() {
        let book = Audiobook(title: "Test", folderName: "test")
        book.equalizerConfiguration = EqualizerConfiguration(
            isEnabled: true,
            preset: .custom,
            preampDB: 99,
            bandGainsDB: [99, -99, 0, 0, 0]
        )
        let read = book.equalizerConfiguration
        #expect(read.preampDB == EqualizerConfiguration.preampRange.upperBound)
        #expect(read.bandGainsDB[0] == EqualizerConfiguration.bandRange.upperBound)
        #expect(read.bandGainsDB[1] == EqualizerConfiguration.bandRange.lowerBound)
    }

}
