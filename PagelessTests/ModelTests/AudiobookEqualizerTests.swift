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

    @Test func settingConfigurationPersistsThroughGetter() {
        let book = Audiobook(title: "Test", folderName: "test")
        var custom = EqualizerConfiguration(
            isEnabled: true,
            preset: .voiceBoost,
            preampDB: 6,
            bandGainsDB: [-2, 0, 4, 5, 1]
        )
        custom.clamp()

        book.equalizerConfiguration = custom
        let readBack = book.equalizerConfiguration
        #expect(readBack == custom)
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

    @Test func multipleBooksKeepIndependentEqualizerState() {
        let bookA = Audiobook(title: "A", folderName: "a")
        let bookB = Audiobook(title: "B", folderName: "b")

        bookA.equalizerConfiguration = EqualizerConfiguration.preset(.bassBoost, preampDB: 4, isEnabled: true)
        bookB.equalizerConfiguration = EqualizerConfiguration.preset(.trebleBoost, preampDB: 2, isEnabled: true)

        #expect(bookA.equalizerConfiguration.preset == .bassBoost)
        #expect(bookB.equalizerConfiguration.preset == .trebleBoost)
        #expect(bookA.equalizerConfiguration.preampDB == 4)
        #expect(bookB.equalizerConfiguration.preampDB == 2)
    }
}
