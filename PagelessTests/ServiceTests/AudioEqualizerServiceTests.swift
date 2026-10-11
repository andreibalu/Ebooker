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
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
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

}
