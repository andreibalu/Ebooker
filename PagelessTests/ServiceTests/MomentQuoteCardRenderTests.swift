//
//  MomentQuoteCardRenderTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Isolated on purpose: the card is built inside a share closure, so E2E can't reach its bytes
/// or its failure path (the share sheet shows nothing for a thrown error).
@MainActor
struct MomentQuoteCardRenderTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // Failure: the off-screen render returned nil or empty data (an unresolved dynamic color, a
    // zero-size view), so the share sheet offered an empty or missing PNG.
    @Test func rendersNonEmptyPNGForSavedMomentWithDraft() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "Moby-Dick", author: "Melville", folderName: "moby", totalDuration: 600)
        context.insert(book)
        let moment = Moment(trackIndex: 0, time: 75, label: "Saved label", audiobook: book)
        moment.notes = "Saved note"
        moment.quoteLine = "Saved quote"
        context.insert(moment)
        try context.save()

        let draft = MomentQuoteCardDraft(label: "Draft label", note: "Draft note", quoteLine: "\"Call me Ishmael.\"")
        let image = MomentQuoteCardImage(moment: moment, container: container, draft: draft)
        let data = try image.renderPNGData()

        #expect(data.count > 1_000)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    // Failure: the share used the saved text instead of what the open edit sheet shows, or kept
    // the stored quote's own quote marks (a doubled opening mark on the card).
    @Test func payloadTakesDraftLabelNoteAndQuote() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "Moby-Dick", author: "Melville", folderName: "moby", totalDuration: 600)
        context.insert(book)
        let moment = Moment(trackIndex: 0, time: 75, label: "Saved label", audiobook: book)
        moment.notes = "Saved note"
        moment.quoteLine = "Saved quote"
        context.insert(moment)

        let draft = MomentQuoteCardDraft(label: "  Draft label ", note: "Draft note", quoteLine: "\"Call me Ishmael.\"")
        let payload = MomentQuoteCardPayload(moment: moment, audiobook: book, draft: draft)
        #expect(payload.label == "Draft label")
        #expect(payload.note == "Draft note")
        #expect(payload.quoteLine == "Call me Ishmael.")
        #expect(payload.bookTitle == "Moby-Dick")

        let saved = MomentQuoteCardPayload(moment: moment, audiobook: book, draft: nil)
        #expect(saved.label == "Saved label")
        #expect(saved.note == "Saved note")
        #expect(saved.quoteLine == "Saved quote")

        // An emptied draft field wins over the stored one, and a blank draft label falls back.
        let blank = MomentQuoteCardPayload(
            moment: moment, audiobook: book,
            draft: MomentQuoteCardDraft(label: "  ", note: nil, quoteLine: nil)
        )
        #expect(blank.label == "Saved label")
        #expect(blank.note == nil)
        #expect(blank.quoteLine == nil)
    }

    // Failure: `model(for:)` returns a model for a deleted row and reading it traps, so sharing a
    // moment deleted on another device (or by sync) crashed the app instead of sharing nothing.
    @Test func deletedMomentThrowsInsteadOfCrashing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "Moby-Dick", author: "Melville", folderName: "moby", totalDuration: 600)
        context.insert(book)
        let moment = Moment(trackIndex: 0, time: 75, label: "Doomed", audiobook: book)
        context.insert(moment)
        try context.save()
        let image = MomentQuoteCardImage(moment: moment, container: container)

        // Deleted but not yet saved.
        context.delete(moment)
        #expect(throws: (any Error).self) { try image.renderPNGData() }

        // Deleted and saved.
        try context.save()
        #expect(throws: (any Error).self) { try image.renderPNGData() }
    }

    // Failure: the Markdown export resolved the book the same unsafe way.
    @Test func deletedBookMakesMarkdownExportThrow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "Gone", author: "A", folderName: "gone", totalDuration: 60)
        context.insert(book)
        try context.save()
        let export = MomentsMarkdownExport(book: book, container: container)

        context.delete(book)
        try context.save()
        #expect(throws: (any Error).self) { try export.renderMarkdown() }
    }
}
