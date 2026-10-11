//
//  AudiobookEqualizerTests.swift
//  PagelessTests
//

import Testing
@testable import Pageless

struct AudiobookEqualizerTests {
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
