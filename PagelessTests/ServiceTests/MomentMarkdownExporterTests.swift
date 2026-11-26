//
//  MomentMarkdownExporterTests.swift
//  PagelessTests
//
//  Created for Slice 02: Moments Transcripts, Inline Metadata & Quote Sharing.
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Isolated on purpose: E2E cannot inspect the exported `.md` bytes inside the system share sheet.
struct MomentMarkdownExporterTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // Nov 14, 2023 in UTC
    private static let testLocale = Locale(identifier: "en_US_POSIX")
    private static let testTimeZone = TimeZone(secondsFromGMT: 0)!

    @Test func ordersPinnedFirstThenTrackThenTime() {
        let entries = [
            MomentMarkdownExporter.Entry(
                label: "Track 1 Later",
                chapterTitle: "Chapter 2",
                time: 120,
                trackIndex: 1,
                isPinned: false,
                quoteLine: nil,
                notes: nil,
                moodName: nil,
                categoryNames: [],
                characters: [],
                transcript: nil
            ),
            MomentMarkdownExporter.Entry(
                label: "Track 0 Unpinned",
                chapterTitle: "Chapter 1",
                time: 30,
                trackIndex: 0,
                isPinned: false,
                quoteLine: nil,
                notes: nil,
                moodName: nil,
                categoryNames: [],
                characters: [],
                transcript: nil
            ),
            MomentMarkdownExporter.Entry(
                label: "Pinned Later Track",
                chapterTitle: "Chapter 3",
                time: 10,
                trackIndex: 2,
                isPinned: true,
                quoteLine: nil,
                notes: nil,
                moodName: nil,
                categoryNames: [],
                characters: [],
                transcript: nil
            ),
            MomentMarkdownExporter.Entry(
                label: "Track 1 Earlier",
                chapterTitle: "Chapter 2",
                time: 45,
                trackIndex: 1,
                isPinned: false,
                quoteLine: nil,
                notes: nil,
                moodName: nil,
                categoryNames: [],
                characters: [],
                transcript: nil
            ),
        ]

        let md = MomentMarkdownExporter.markdown(
            bookTitle: "Sample Book",
            author: "Jane Doe",
            entries: entries,
            exportDate: Self.fixedDate,
            locale: Self.testLocale,
            timeZone: Self.testTimeZone
        )

        let expectedOrder = [
            "## Pinned Later Track",
            "## Track 0 Unpinned",
            "## Track 1 Earlier",
            "## Track 1 Later",
        ]
        var lastIndex = md.startIndex
        for heading in expectedOrder {
            let range = md.range(of: heading, range: lastIndex..<md.endIndex)
            #expect(range != nil, "Missing heading \(heading) in order")
            if let range {
                lastIndex = range.upperBound
            }
        }
    }

    @Test func formatsFullMomentWithMultilineQuoteTagsCharactersAndTranscript() {
        let entry = MomentMarkdownExporter.Entry(
            label: "Line one\nLine two",
            chapterTitle: "Chapter 1",
            time: 65,
            trackIndex: 0,
            isPinned: true,
            quoteLine: "First quote line\nSecond quote line",
            notes: "Important reflection on #1 *theme* > rest.",
            moodName: "Tense",
            categoryNames: ["Dialogue", "Plot Twist"],
            characters: ["Alice", "Bob"],
            transcript: "Spoken words with emoji 🎙️ and *stars*."
        )

        let md = MomentMarkdownExporter.markdown(
            bookTitle: "My Book",
            author: "A. Author",
            entries: [entry],
            exportDate: Self.fixedDate,
            locale: Self.testLocale,
            timeZone: Self.testTimeZone
        )

        let expected = """
        # My Book

        *by A. Author*

        Exported from Unpaged on November 14, 2023

        ## Line one Line two

        Chapter 1 · 01:05 · Pinned

        > First quote line
        > Second quote line

        Important reflection on #1 *theme* > rest.

        Tags: Tense, Dialogue, Plot Twist

        Characters: Alice, Bob

        **Transcript:** Spoken words with emoji 🎙️ and *stars*.
        """ + "\n"

        #expect(md == expected)
    }

    @Test func omitsEmptyAuthorAndWhitespaceOnlyFieldsAndPreservesSpecialChars() {
        let entry = MomentMarkdownExporter.Entry(
            label: "Moment #1 *special* > 🔥",
            chapterTitle: "Intro",
            time: 5,
            trackIndex: 0,
            isPinned: false,
            quoteLine: "   \n  ",
            notes: "",
            moodName: "  ",
            categoryNames: ["", "   "],
            characters: ["  "],
            transcript: "\t"
        )

        let md = MomentMarkdownExporter.markdown(
            bookTitle: "Solo Title",
            author: "   ",
            entries: [entry],
            exportDate: Self.fixedDate,
            locale: Self.testLocale,
            timeZone: Self.testTimeZone
        )

        let expected = """
        # Solo Title

        Exported from Unpaged on November 14, 2023

        ## Moment #1 *special* > 🔥

        Intro · 00:05
        """ + "\n"

        #expect(md == expected)
        #expect(!md.contains("*by"))
        #expect(!md.contains("Tags:"))
        #expect(!md.contains("Characters:"))
        #expect(!md.contains("**Transcript:**"))
    }

    @MainActor
    @Test func bookConvenienceHandlesUnavailableTrackAndSanitizesFilename() throws {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let book = Audiobook(title: "Part 1/2: The Beginning", author: "Writer", folderName: "part1", totalDuration: 300)
        context.insert(book)
        let moment = Moment(trackIndex: 3, time: 90, label: "Missing Track Moment", audiobook: book)
        context.insert(moment)

        let md = MomentMarkdownExporter.markdown(for: book, exportDate: Self.fixedDate)
        #expect(md.contains("Track unavailable · 01:30"))

        let export = MomentsMarkdownExport(book: book, exportDate: Self.fixedDate)
        #expect(!export.suggestedFilename.contains("/"))
        #expect(!export.suggestedFilename.contains(":"))
        #expect(export.suggestedFilename.hasSuffix("Moments.md"))
    }
}
