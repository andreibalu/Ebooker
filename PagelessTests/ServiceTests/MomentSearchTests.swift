//
//  MomentSearchTests.swift
//  PagelessTests
//
//  Created for Slice 02: Moments Transcripts, Inline Metadata & Quote Sharing.
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Isolated on purpose: E2E cannot exhaustively test scoring weights, diacritic folding,
/// and start/middle/end snippet windowing across edge-case transcripts.
@MainActor
struct MomentSearchTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func transcriptOnlyWordMatchesAndRanksBelowTitleAndNotes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "The Odyssey", author: "Homer", folderName: "odyssey", totalDuration: 600)
        context.insert(book)

        let titleHit = Moment(trackIndex: 0, time: 10, label: "Lighthouse Scene", audiobook: book)
        let noteHit = Moment(trackIndex: 0, time: 20, label: "Harbor", audiobook: book, notes: "Near the lighthouse")
        let transcriptHit = Moment(trackIndex: 0, time: 30, label: "Coastline", audiobook: book,
                                   transcript: "They spotted the distant lighthouse through the fog.")
        context.insert(titleHit)
        context.insert(noteHit)
        context.insert(transcriptHit)

        let words = MomentSearch.words("lighthouse")
        let titleScore = MomentSearch.score(titleHit, words: words)
        let noteScore = MomentSearch.score(noteHit, words: words)
        let transcriptScore = MomentSearch.score(transcriptHit, words: words)

        #expect(titleScore == 10)
        #expect(noteScore == 2)
        #expect(transcriptScore == 1)
    }

    @Test func multiWordQuerySpansLabelAndTranscript() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "The Odyssey", author: "Homer", folderName: "odyssey", totalDuration: 600)
        context.insert(book)

        let moment = Moment(
            trackIndex: 0,
            time: 45,
            label: "Storm at Sea",
            audiobook: book,
            transcript: "The lantern swung wildly as the waves rose."
        )
        context.insert(moment)

        let words = MomentSearch.words("storm lantern")
        #expect(MomentSearch.score(moment, words: words) == 11)
        #expect(MomentSearch.score(moment, words: MomentSearch.words("storm missing")) == nil)
    }

    @Test func diacriticInsensitiveTranscriptSearchAndSnippet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "Paris Stories", author: "Author", folderName: "paris", totalDuration: 600)
        context.insert(book)

        let moment = Moment(
            trackIndex: 0,
            time: 12,
            label: "Morning Walk",
            audiobook: book,
            transcript: "They met outside the small Café on the boulevard."
        )
        context.insert(moment)

        let words = MomentSearch.words("cafe")
        #expect(MomentSearch.score(moment, words: words) == 1)

        let snippet = MomentSearch.transcriptSnippet(for: moment, query: "cafe")
        #expect(snippet == "They met outside the small Café on the boulevard.")
    }

    @Test func snippetWindowingAtStartMiddleEnd() {
        let words = (1...25).map { "w\($0)" }
        let transcript = words.joined(separator: " ")

        let startSnippet = MomentSearch.transcriptSnippet(transcript, words: ["w2"], radius: 8)
        #expect(startSnippet == "w1 w2 w3 w4 w5 w6 w7 w8 w9 w10…")

        let middleSnippet = MomentSearch.transcriptSnippet(transcript, words: ["w13"], radius: 8)
        #expect(middleSnippet == "…w5 w6 w7 w8 w9 w10 w11 w12 w13 w14 w15 w16 w17 w18 w19 w20 w21…")

        let endSnippet = MomentSearch.transcriptSnippet(transcript, words: ["w24"], radius: 8)
        #expect(endSnippet == "…w16 w17 w18 w19 w20 w21 w22 w23 w24 w25")

        let noMatch = MomentSearch.transcriptSnippet(transcript, words: ["absent"], radius: 8)
        #expect(noMatch == nil)
    }

    @Test func snippetNilWhenWordIsVisibleInRowFields() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "Book", author: "Writer", folderName: "book", totalDuration: 600)
        context.insert(book)

        let moment = Moment(
            trackIndex: 0,
            time: 10,
            label: "Visible Label",
            audiobook: book,
            transcript: "Visible label and hidden lighthouse in the transcript.",
            notes: "Visible note",
            categories: [.quote],
            quoteLine: "Visible quote",
            characters: ["Elizabeth"],
            mood: .tense
        )
        context.insert(moment)

        #expect(MomentSearch.transcriptSnippet(for: moment, query: "label") == nil)
        #expect(MomentSearch.transcriptSnippet(for: moment, query: "note") == nil)
        #expect(MomentSearch.transcriptSnippet(for: moment, query: "quote") == nil)
        #expect(MomentSearch.transcriptSnippet(for: moment, query: "elizabeth") == nil)
        #expect(MomentSearch.transcriptSnippet(for: moment, query: "tense") == nil)

        // Mixed query: "label" is visible, "lighthouse" is transcript-only -> snippet should appear.
        let mixed = MomentSearch.transcriptSnippet(for: moment, query: "label lighthouse")
        #expect(mixed == "Visible label and hidden lighthouse in the transcript.")
    }

    // Failure: a spoken mention outranked an explicit tag (metadata scored 0, so it never counted).
    @Test func metadataScoresLikeNotesAndAboveTranscript() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "The Odyssey", author: "Homer", folderName: "odyssey", totalDuration: 600)
        context.insert(book)

        let tagged = Moment(trackIndex: 0, time: 10, label: "Harbor", audiobook: book,
                            categories: [.dialogue], characters: ["Marlow"], mood: .tense)
        let spoken = Moment(trackIndex: 0, time: 20, label: "Coast", audiobook: book,
                            transcript: "Marlow said dialogue was tense.")
        context.insert(tagged)
        context.insert(spoken)

        for word in ["marlow", "dialogue", "tense"] {
            let words = MomentSearch.words(word)
            #expect(MomentSearch.score(tagged, words: words) == 2)
            #expect(MomentSearch.score(spoken, words: words) == 1)
        }
    }

    // Failure: the search view shows and highlights the book title and author in the group header,
    // so a transcript snippet for those words repeats what the reader already sees.
    @Test func snippetNilWhenWordIsInBookTitleOrAuthor() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = Audiobook(title: "The Odyssey", author: "Homer", folderName: "odyssey", totalDuration: 600)
        context.insert(book)
        let moment = Moment(trackIndex: 0, time: 5, label: "Coast", audiobook: book,
                            transcript: "Homer sang of the Odyssey and the lighthouse.")
        context.insert(moment)

        #expect(MomentSearch.transcriptSnippet(for: moment, query: "odyssey") == nil)
        #expect(MomentSearch.transcriptSnippet(for: moment, query: "homer") == nil)
        #expect(MomentSearch.transcriptSnippet(for: moment, query: "homer lighthouse")?.contains("lighthouse") == true)
    }
}
