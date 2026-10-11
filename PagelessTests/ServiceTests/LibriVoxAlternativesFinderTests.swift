//
//  LibriVoxAlternativesFinderTests.swift
//  PagelessTests
//

import Testing
import Foundation
import SwiftData
@testable import Pageless

/// Covers "Other Recordings" matching: normalized-title grouping of LibriVox
/// re-recordings of the same text (same author + language), conservative about
/// parentheticals so different translations are never merged.
struct LibriVoxAlternativesFinderTests {

    // MARK: - normalizedTitleKey

    @Test func keepsUnknownParentheticals() {
        // Different translations are different texts — must NOT merge.
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("The Iliad (Pope Translation)") == "the iliad (pope translation)")
    }

    // MARK: - alternatives(to:context:)

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LibriVoxBook.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, ModelContext(container))
    }

    private func makeBook(
        id: String,
        title: String,
        author: String = "Emily Brontë",
        language: String = "English"
    ) -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: title,
            authorDisplay: author,
            bookDescription: "",
            language: language,
            totalTimeSecs: 3600
        )
    }

    @Test func excludesOtherLanguages() throws {
        let (container, context) = try makeContext()
        _ = container
        let english = makeBook(id: "1", title: "Wuthering Heights")
        let german = makeBook(id: "2", title: "Wuthering Heights (version 2)", language: "German")
        [english, german].forEach { context.insert($0) }
        try context.save()

        #expect(LibriVoxAlternativesFinder.alternatives(to: english, context: context).isEmpty)
    }

    @Test func excludesOtherAuthors() throws {
        let (container, context) = try makeContext()
        _ = container
        let bronte = makeBook(id: "1", title: "Poems")
        let poe = makeBook(id: "2", title: "Poems", author: "Edgar Allan Poe")
        [bronte, poe].forEach { context.insert($0) }
        try context.save()

        #expect(LibriVoxAlternativesFinder.alternatives(to: bronte, context: context).isEmpty)
    }
}
