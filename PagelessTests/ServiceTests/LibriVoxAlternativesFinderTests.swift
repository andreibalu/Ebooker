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

    @Test func stripsVersionSuffix() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Wuthering Heights (version 2)") == "wuthering heights")
    }

    @Test func stripsVersionSuffixCaseInsensitive() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Wuthering Heights (Version 12)") == "wuthering heights")
    }

    @Test func stripsDramaticReadingSuffix() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Hamlet (dramatic reading)") == "hamlet")
    }

    @Test func stripsAbridgementSuffixes() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Moby Dick (abridged)") == "moby dick")
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Moby Dick (unabridged)") == "moby dick")
    }

    @Test func stripsCombinedVersionDramaticReadingSuffix() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("A Christmas Carol (version 5 dramatic reading)") == "a christmas carol")
    }

    @Test func stripsStackedSuffixes() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Hamlet (dramatic reading) (version 2)") == "hamlet")
    }

    @Test func keepsUnknownParentheticals() {
        // Different translations are different texts — must NOT merge.
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("The Iliad (Pope Translation)") == "the iliad (pope translation)")
    }

    @Test func foldsDiacriticsAndCase() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("Brontë Poems") == "bronte poems")
    }

    @Test func collapsesWhitespace() {
        #expect(LibriVoxAlternativesFinder.normalizedTitleKey("  Wuthering   Heights  ") == "wuthering heights")
    }

    // MARK: - versionLabel

    @Test func versionLabelNilForOriginal() {
        #expect(LibriVoxAlternativesFinder.versionLabel("Wuthering Heights") == nil)
    }

    @Test func versionLabelForVersionSuffix() {
        #expect(LibriVoxAlternativesFinder.versionLabel("Wuthering Heights (version 2)") == "Version 2")
    }

    @Test func versionLabelForDramaticReading() {
        #expect(LibriVoxAlternativesFinder.versionLabel("Hamlet (Dramatic Reading)") == "Dramatic Reading")
    }

    @Test func versionLabelNilForUnknownParenthetical() {
        #expect(LibriVoxAlternativesFinder.versionLabel("The Iliad (Pope Translation)") == nil)
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

    @Test func findsOtherVersionsExcludingSelf() throws {
        let (container, context) = try makeContext()
        _ = container
        let original = makeBook(id: "1", title: "Wuthering Heights")
        let v2 = makeBook(id: "2", title: "Wuthering Heights (version 2)")
        let v3 = makeBook(id: "3", title: "Wuthering Heights (version 3)")
        [original, v2, v3].forEach { context.insert($0) }
        try context.save()

        let found = LibriVoxAlternativesFinder.alternatives(to: original, context: context)
        #expect(found.map(\.id) == ["2", "3"])
    }

    @Test func findsOriginalFromAVersionedEntry() throws {
        let (container, context) = try makeContext()
        _ = container
        let original = makeBook(id: "1", title: "Wuthering Heights")
        let v2 = makeBook(id: "2", title: "Wuthering Heights (version 2)")
        let v3 = makeBook(id: "3", title: "Wuthering Heights (version 3)")
        [original, v2, v3].forEach { context.insert($0) }
        try context.save()

        let found = LibriVoxAlternativesFinder.alternatives(to: v2, context: context)
        #expect(found.map(\.id) == ["1", "3"])
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

    @Test func sortsOriginalThenVersionsThenOtherReadings() throws {
        let (container, context) = try makeContext()
        _ = container
        let dramatic = makeBook(id: "d", title: "Wuthering Heights (dramatic reading)")
        let v3 = makeBook(id: "3", title: "Wuthering Heights (version 3)")
        let original = makeBook(id: "1", title: "Wuthering Heights")
        let v2 = makeBook(id: "2", title: "Wuthering Heights (version 2)")
        let v10 = makeBook(id: "10", title: "Wuthering Heights (version 10)")
        let current = makeBook(id: "c", title: "Wuthering Heights (version 99)")
        [dramatic, v3, original, v2, v10, current].forEach { context.insert($0) }
        try context.save()

        let found = LibriVoxAlternativesFinder.alternatives(to: current, context: context)
        #expect(found.map(\.id) == ["1", "2", "3", "10", "d"])
    }
}
