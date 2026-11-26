//
//  MomentMarkdownExporter.swift
//  Pageless
//
//  Created for Slice 02: Moments Transcripts, Inline Metadata & Quote Sharing.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MomentMarkdownExporter {
    struct Entry: Sendable, Equatable {
        let label: String
        let chapterTitle: String
        let time: Double
        let trackIndex: Int
        let isPinned: Bool
        let quoteLine: String?
        let notes: String?
        let moodName: String?
        let categoryNames: [String]
        let characters: [String]
        let transcript: String?
    }

    static func markdown(
        bookTitle: String,
        author: String,
        entries: [Entry],
        exportDate: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var blocks: [String] = []

        let cleanTitle = collapsedSingleLine(bookTitle)
        blocks.append("# \(cleanTitle.isEmpty ? "Untitled" : cleanTitle)")

        if let cleanAuthor = trimmed(author) {
            blocks.append("*by \(cleanAuthor)*")
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        blocks.append("Exported from Unpaged on \(formatter.string(from: exportDate))")

        let sorted = entries.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.trackIndex != rhs.trackIndex { return lhs.trackIndex < rhs.trackIndex }
            return lhs.time < rhs.time
        }

        for entry in sorted {
            let label = collapsedSingleLine(entry.label)
            blocks.append("## \(label.isEmpty ? "Moment" : label)")

            let chapter = collapsedSingleLine(entry.chapterTitle)
            let clock = TimeFormatter.clockString(seconds: entry.time)
            let pinSuffix = entry.isPinned ? " · Pinned" : ""
            blocks.append("\(chapter.isEmpty ? "Track unavailable" : chapter) · \(clock)\(pinSuffix)")

            if let quote = trimmed(entry.quoteLine) {
                let quotedLines = quote
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "> \($0)" }
                    .joined(separator: "\n")
                blocks.append(quotedLines)
            }

            if let notes = trimmed(entry.notes) {
                blocks.append(notes)
            }

            let tags = ([trimmed(entry.moodName)].compactMap { $0 }) + entry.categoryNames.compactMap(trimmed)
            if !tags.isEmpty {
                blocks.append("Tags: \(tags.joined(separator: ", "))")
            }

            let characters = entry.characters.compactMap(trimmed)
            if !characters.isEmpty {
                blocks.append("Characters: \(characters.joined(separator: ", "))")
            }

            if let transcript = trimmed(entry.transcript) {
                blocks.append("**Transcript:** \(transcript)")
            }
        }

        return blocks.joined(separator: "\n\n") + "\n"
    }

    @MainActor
    static func markdown(
        for book: Audiobook,
        exportDate: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        markdown(
            bookTitle: book.title,
            author: book.author,
            entries: entries(for: book),
            exportDate: exportDate,
            locale: locale,
            timeZone: timeZone
        )
    }

    @MainActor
    static func entries(for book: Audiobook) -> [Entry] {
        let tracks = book.sortedTracks
        return book.moments.map { moment in
            let chapterTitle = tracks.indices.contains(moment.trackIndex)
                ? tracks[moment.trackIndex].displayTitle
                : "Track unavailable"
            return Entry(
                label: moment.label,
                chapterTitle: chapterTitle,
                time: moment.time,
                trackIndex: moment.trackIndex,
                isPinned: moment.isPinned,
                quoteLine: moment.quoteLine,
                notes: moment.notes,
                moodName: moment.mood?.displayName,
                categoryNames: moment.categories.map(\.displayName),
                characters: moment.characters,
                transcript: moment.transcript
            )
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func collapsedSingleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Renders the per-book Markdown export lazily only when the user actually triggers sharing.
struct MomentsMarkdownExport: Transferable, Sendable {
    let bookTitle: String
    let author: String
    let entries: [MomentMarkdownExporter.Entry]
    let exportDate: Date

    var suggestedFilename: String {
        let sanitized = bookTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "Book" : sanitized
        return "\(base) Moments.md"
    }

    @MainActor
    init(book: Audiobook, exportDate: Date = .now) {
        self.bookTitle = book.title
        self.author = book.author
        self.entries = MomentMarkdownExporter.entries(for: book)
        self.exportDate = exportDate
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType("net.daringfireball.markdown") ?? .plainText) { item in
            let text = MomentMarkdownExporter.markdown(
                bookTitle: item.bookTitle,
                author: item.author,
                entries: item.entries,
                exportDate: item.exportDate
            )
            return Data(text.utf8)
        }
        .suggestedFileName { item in
            item.suggestedFilename
        }
    }
}
