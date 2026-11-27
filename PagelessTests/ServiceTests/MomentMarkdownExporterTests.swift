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

    @Test func omitsEmptyAuthorAndWhitespaceOnlyFieldsAndEscapesInlineHeadingChars() {
        let entry = MomentMarkdownExporter.Entry(
            label: "Moment #1 *special* [x] `y` _z_ > 🔥",
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

        ## Moment #1 \\*special\\* \\[x\\] \\`y\\` \\_z\\_ > 🔥

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

        let export = MomentsMarkdownExport(book: book, container: container, exportDate: Self.fixedDate)
        #expect(!export.suggestedFilename.contains("/"))
        #expect(!export.suggestedFilename.contains(":"))
        #expect(export.suggestedFilename.hasSuffix("Moments.md"))

        // The transfer closure reads the book when sharing, not when the export value was built.
        moment.label = "Renamed Before Sharing"
        let rendered = try export.renderMarkdown()
        #expect(rendered.contains("## Renamed Before Sharing"))
        #expect(rendered.contains("2023"))
    }

    // Failure: user text emitted raw turns a note into a heading, list, quote or rule, and a
    // multi-line note collapses into one paragraph.
    @Test func escapesLeadingBlockMarkersAndKeepsLineBreaks() {
        let notes = "# Not a heading\r\n> not a quote\r- not a list\n+ plus\n* star\n= eq\n3. third\n4) fourth\n---\n===\n\n  indented\nplain #1 mid"
        let entry = MomentMarkdownExporter.Entry(
            label: "L", chapterTitle: "Ch", time: 1, trackIndex: 0, isPinned: false,
            quoteLine: "# q1\n- q2", notes: notes, moodName: nil, categoryNames: [], characters: [],
            transcript: "first line\n## second\n<!-- spoiler\nthird"
        )
        let md = MomentMarkdownExporter.markdown(
            bookTitle: "B", author: "", entries: [entry],
            exportDate: Self.fixedDate, locale: Self.testLocale, timeZone: Self.testTimeZone
        )
        let expectedNotes = [
            "\\# Not a heading  ", "\\> not a quote  ", "\\- not a list  ", "\\+ plus  ", "\\* star  ",
            "\\= eq  ", "3\\. third  ", "4\\) fourth  ", "\\---  ", "\\===", "", "indented  ", "plain #1 mid",
        ].joined(separator: "\n")
        #expect(md.contains("\n\n" + expectedNotes + "\n\n"))
        #expect(md.contains("> \\# q1  \n> \\- q2\n"))
        // A leading "<" could open a raw HTML block ("<!--") that hides every later moment.
        #expect(md.contains("**Transcript:** first line  \n\\## second  \n\\<!-- spoiler  \nthird\n"))
        #expect(!md.contains("\r"))
    }

    // Failure: `*`, `_`, backticks and brackets in a label or chapter title restyle or link the heading.
    @Test func escapesInlineMarkupInHeadingAndChapterLine() {
        let entry = MomentMarkdownExporter.Entry(
            label: "A *b* _c_ `d` [e](f)", chapterTitle: "# Part *1* [x]", time: 1, trackIndex: 0,
            isPinned: false, quoteLine: nil, notes: nil, moodName: nil, categoryNames: [], characters: [],
            transcript: nil
        )
        let md = MomentMarkdownExporter.markdown(
            bookTitle: "B", author: "", entries: [entry],
            exportDate: Self.fixedDate, locale: Self.testLocale, timeZone: Self.testTimeZone
        )
        #expect(md.contains("## A \\*b\\* \\_c\\_ \\`d\\` \\[e\\](f)\n"))
        #expect(md.contains("\n\\# Part \\*1\\* \\[x\\] · 00:01\n"))
    }

    // Failure: spaced or underscore/asterisk rules ("_ _ _", "* * *", "- - -", "***") stayed raw
    // and drew a horizontal rule (or, under a paragraph line, a setext heading) through the notes.
    @Test func escapesSpacedThematicBreaksAndSetextUnderlines() {
        let notes = "_ _ _\n* * *\n- - -\n***\n___\n-\t-\t-\n--\n**bold** start"
        let entry = MomentMarkdownExporter.Entry(
            label: "L", chapterTitle: "Ch", time: 1, trackIndex: 0, isPinned: false,
            quoteLine: nil, notes: notes, moodName: nil, categoryNames: [], characters: [], transcript: nil
        )
        let md = MomentMarkdownExporter.markdown(
            bookTitle: "B", author: "", entries: [entry],
            exportDate: Self.fixedDate, locale: Self.testLocale, timeZone: Self.testTimeZone
        )
        let expected = [
            "\\_ _ _  ", "\\* * *  ", "\\- - -  ", "\\***  ", "\\___  ", "\\-\t-\t-  ", "\\--  ", "**bold** start",
        ].joined(separator: "\n")
        #expect(md.contains("\n\n" + expected + "\n"))
    }

    // Failure: escaping every leading digit, "-", "+" or "*" showed a stray backslash in "3.14",
    // "-5" or "-ish" in viewers that print unknown escapes, and noised the file.
    @Test func leavesNonMarkersAsTyped() {
        let notes = "3.14 is pi\n-5 degrees\n-ish\n+1 vote\n*emphasis* first\n2023 was a year\n7) item\n8.\n-\n*"
        let entry = MomentMarkdownExporter.Entry(
            label: "L", chapterTitle: "3.5 Ch", time: 1, trackIndex: 0, isPinned: false,
            quoteLine: nil, notes: notes, moodName: nil, categoryNames: [], characters: [], transcript: nil
        )
        let md = MomentMarkdownExporter.markdown(
            bookTitle: "B", author: "", entries: [entry],
            exportDate: Self.fixedDate, locale: Self.testLocale, timeZone: Self.testTimeZone
        )
        let expected = [
            "3.14 is pi  ", "-5 degrees  ", "-ish  ", "+1 vote  ", "*emphasis* first  ",
            "2023 was a year  ", "7\\) item  ", "8\\.  ", "\\-  ", "\\*",
        ].joined(separator: "\n")
        #expect(md.contains("\n\n" + expected + "\n"))
        #expect(md.contains("\n3.5 Ch · 00:01\n"))
    }

    // Failure: "## Track 3 #" lost its "#" (the renderer reads it as a closing sequence), and a label
    // of only "#"s became an empty heading.
    @Test func escapesClosingHashSequenceInHeadings() {
        func md(label: String, title: String = "B") -> String {
            let entry = MomentMarkdownExporter.Entry(
                label: label, chapterTitle: "Ch", time: 1, trackIndex: 0, isPinned: false,
                quoteLine: nil, notes: nil, moodName: nil, categoryNames: [], characters: [], transcript: nil
            )
            return MomentMarkdownExporter.markdown(
                bookTitle: title, author: "", entries: [entry],
                exportDate: Self.fixedDate, locale: Self.testLocale, timeZone: Self.testTimeZone
            )
        }
        #expect(md(label: "Track 3 #").contains("\n## Track 3 \\#\n"))
        #expect(md(label: "Track 3 ##").contains("\n## Track 3 \\##\n"))
        #expect(md(label: "###").contains("\n## \\###\n"))
        #expect(md(label: "Part 1", title: "Book #").hasPrefix("# Book \\#\n"))
        // Not closing sequences: no space before the run, or the run is not at the end.
        #expect(md(label: "C#").contains("\n## C#\n"))
        #expect(md(label: "# one").contains("\n## # one\n"))
    }

    // Failure: a newline or leading dot in the title made a multi-line or hidden file name.
    @Test func filenameCollapsesNewlinesAndTrimsLeadingDots() {
        #expect(MomentsMarkdownExport.filename(forBookTitle: "Line one\nLine two") == "Line one Line two Moments.md")
        #expect(MomentsMarkdownExport.filename(forBookTitle: "Win\r\nLose\rDraw") == "Win Lose Draw Moments.md")
        #expect(MomentsMarkdownExport.filename(forBookTitle: "..hidden") == "hidden Moments.md")
        #expect(MomentsMarkdownExport.filename(forBookTitle: " . ..") == "Book Moments.md")
        #expect(MomentsMarkdownExport.filename(forBookTitle: "Part 1/2: Start") == "Part 1-2- Start Moments.md")
    }
}
