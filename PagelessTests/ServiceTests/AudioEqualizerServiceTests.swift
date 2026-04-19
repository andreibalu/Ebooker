//
//  AudioEqualizerServiceTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

@MainActor
struct AudioEqualizerServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func initialStateIsDisabledAndFlat() {
        let service = AudioEqualizerService()
        #expect(service.isEnabled == false)
        #expect(service.preset == .flat)
        #expect(service.preampDB == 0)
        #expect(service.bandGainsDB == EqualizerPreset.flat.bandGainsDB)
    }

    @Test func bindLoadsSavedConfigurationFromAudiobook() throws {
        let context = try makeContext()
        let service = AudioEqualizerService()
        service.configure(modelContext: context)

        let book = Audiobook(title: "Quiet Book", folderName: "q")
        book.equalizerConfiguration = EqualizerConfiguration.preset(.voiceBoost, preampDB: 6, isEnabled: true)
        context.insert(book)

        service.bind(to: book)
        #expect(service.isEnabled == true)
        #expect(service.preset == .voiceBoost)
        #expect(service.preampDB == 6)
        #expect(service.bandGainsDB == EqualizerPreset.voiceBoost.bandGainsDB)
    }

    @Test func applyPresetUpdatesBandsAndPersists() throws {
        let context = try makeContext()
        let service = AudioEqualizerService()
        service.configure(modelContext: context)

        let book = Audiobook(title: "Book", folderName: "b")
        context.insert(book)
        service.bind(to: book)

        service.applyPreset(.bassBoost)
        #expect(service.preset == .bassBoost)
        #expect(service.bandGainsDB == EqualizerPreset.bassBoost.bandGainsDB)
        #expect(book.equalizerConfiguration.preset == .bassBoost)
    }

    @Test func manualBandEditFlipsPresetToCustom() throws {
        let context = try makeContext()
        let service = AudioEqualizerService()
        service.configure(modelContext: context)

        let book = Audiobook(title: "Book", folderName: "b")
        context.insert(book)
        service.bind(to: book)

        service.applyPreset(.voiceBoost)
        #expect(service.preset == .voiceBoost)

        service.setBandGain(.low60, dB: 5)
        #expect(service.preset == .custom)
        #expect(service.bandGainsDB[EqualizerBand.low60.rawValue] == 5)
        #expect(book.equalizerConfiguration.preset == .custom)
    }

    @Test func setPreampClampsAndPersists() throws {
        let context = try makeContext()
        let service = AudioEqualizerService()
        service.configure(modelContext: context)

        let book = Audiobook(title: "Book", folderName: "b")
        context.insert(book)
        service.bind(to: book)

        service.setPreamp(99)
        #expect(service.preampDB == EqualizerConfiguration.preampRange.upperBound)
        #expect(book.equalizerConfiguration.preampDB == EqualizerConfiguration.preampRange.upperBound)

        service.setPreamp(-5)
        #expect(service.preampDB == EqualizerConfiguration.preampRange.lowerBound)
    }

    @Test func resetReturnsToFlatWithoutChangingEnabled() throws {
        let context = try makeContext()
        let service = AudioEqualizerService()
        service.configure(modelContext: context)

        let book = Audiobook(title: "Book", folderName: "b")
        context.insert(book)
        service.bind(to: book)
        service.setEnabled(true)
        service.applyPreset(.bassBoost)
        service.setPreamp(6)

        service.reset()
        #expect(service.preset == .flat)
        #expect(service.bandGainsDB == EqualizerPreset.flat.bandGainsDB)
        #expect(service.preampDB == 0)
        #expect(service.isEnabled == true)
    }

    @Test func bindingDifferentBooksIsolatesState() throws {
        let context = try makeContext()
        let service = AudioEqualizerService()
        service.configure(modelContext: context)

        let bookA = Audiobook(title: "A", folderName: "a")
        bookA.equalizerConfiguration = EqualizerConfiguration.preset(.bassBoost, preampDB: 4, isEnabled: true)
        let bookB = Audiobook(title: "B", folderName: "b")
        bookB.equalizerConfiguration = EqualizerConfiguration.preset(.trebleBoost, preampDB: 2, isEnabled: true)
        context.insert(bookA)
        context.insert(bookB)

        service.bind(to: bookA)
        #expect(service.preset == .bassBoost)
        #expect(service.preampDB == 4)

        service.bind(to: bookB)
        #expect(service.preset == .trebleBoost)
        #expect(service.preampDB == 2)

        // Changing state while bound to B does not leak back into A.
        service.setPreamp(8)
        #expect(bookB.equalizerConfiguration.preampDB == 8)
        #expect(bookA.equalizerConfiguration.preampDB == 4)
    }

    @Test func unbindingLeavesStateFlat() {
        let service = AudioEqualizerService()
        let book = Audiobook(title: "A", folderName: "a")
        book.equalizerConfiguration = EqualizerConfiguration.preset(.bassBoost, preampDB: 5, isEnabled: true)
        service.bind(to: book)
        #expect(service.preset == .bassBoost)

        service.bind(to: nil)
        #expect(service.preset == .flat)
        #expect(service.preampDB == 0)
        #expect(service.isEnabled == false)
    }
}
