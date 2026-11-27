//
//  MomentMarkdownExporter.swift
//  Pageless
//
//  Created for Slice 02: Moments Transcripts, Inline Metadata & Quote Sharing.
//

import Foundation
import SwiftData
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

        let cleanTitle = escapedHeadingText(collapsedSingleLine(bookTitle))
        blocks.append("# \(cleanTitle.isEmpty ? "Untitled" : cleanTitle)")

        let cleanAuthor = escapedInline(collapsedSingleLine(author))
        if !cleanAuthor.isEmpty {
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
            let label = escapedHeadingText(collapsedSingleLine(entry.label))
            blocks.append("## \(label.isEmpty ? "Moment" : label)")

            let chapter = escapedInline(collapsedSingleLine(entry.chapterTitle))
            let clock = TimeFormatter.clockString(seconds: entry.time)
            let pinSuffix = entry.isPinned ? " · Pinned" : ""
            // The line starts with the chapter title, so a title like "1. Intro" or "# Part" needs
            // its leading marker escaped as well.
            blocks.append(escapedLeadingMarker("\(chapter.isEmpty ? "Track unavailable" : chapter) · \(clock)\(pinSuffix)"))

            if let quote = trimmed(entry.quoteLine) {
                blocks.append(escapedBlock(quote, linePrefix: "> "))
            }

            if let notes = trimmed(entry.notes) {
                blocks.append(escapedBlock(notes))
            }

            let tags = ([trimmed(entry.moodName)].compactMap { $0 }) + entry.categoryNames.compactMap(trimmed)
            if !tags.isEmpty {
                blocks.append("Tags: \(tags.map { escapedInline(collapsedSingleLine($0)) }.joined(separator: ", "))")
            }

            let characters = entry.characters.compactMap(trimmed)
            if !characters.isEmpty {
                blocks.append("Characters: \(characters.map { escapedInline(collapsedSingleLine($0)) }.joined(separator: ", "))")
            }

            if let transcript = trimmed(entry.transcript) {
                blocks.append(escapedBlock(transcript, firstLinePrefix: "**Transcript:** "))
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

    // MARK: - Markdown escaping

    /// Backslash-escapes the characters that restyle or link a heading, chapter line or tag.
    private static func escapedInline(_ value: String) -> String {
        var result = ""
        for character in value {
            if "\\*_`[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Escapes a block marker at the start of a line (`#`, `>`, lists, rules, setext underlines,
    /// code fences, `1.` / `1)`), so user text can't become a heading, quote, list or rule.
    private static func escapedLeadingMarker(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "#>=`~".contains(first) { return "\\" + line }
        // A list marker needs whitespace or the end of the line after it; "-5" and "-ish" are text.
        if "-+*".contains(first) {
            let next = line.dropFirst().first
            if next == nil || next == " " || next == "\t" { return "\\" + line }
        }
        if isThematicBreakOrSetextUnderline(line) { return "\\" + line }
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, digits.count <= 9,
           let marker = line.dropFirst(digits.count).first, marker == "." || marker == ")" {
            let after = line.dropFirst(digits.count + 1).first
            // "3.14" is a number; only "3. x", "3)" or "3." open a list.
            if after == nil || after == " " || after == "\t" {
                return String(digits) + "\\" + line.dropFirst(digits.count)
            }
        }
        return line
    }

    /// Three or more `-`, `_` or `*` (spaces and tabs between them allowed) draw a rule; one or more
    /// `-` under a paragraph line turn it into a heading, as `=` does for `===`.
    private static func isThematicBreakOrSetextUnderline(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " && $0 != "\t" }
        guard let mark = marks.first, marks.allSatisfy({ $0 == mark }) else { return false }
        switch mark {
        case "-": return true
        case "_", "*": return marks.count >= 3
        default: return false
        }
    }

    /// Inline escaping for an ATX heading's text. A trailing run of `#` after a space (or the whole
    /// text being `#`s) is a closing sequence the renderer strips, so its first `#` is escaped.
    private static func escapedHeadingText(_ value: String) -> String {
        let escaped = escapedInline(value)
        let run = escaped.reversed().prefix(while: { $0 == "#" }).count
        guard run > 0 else { return escaped }
        let runStart = escaped.index(escaped.endIndex, offsetBy: -run)
        let before = escaped[..<runStart].last
        guard before == nil || before == " " || before == "\t" else { return escaped }
        return String(escaped[..<runStart]) + "\\" + String(escaped[runStart...])
    }

    /// Multi-line user text as Markdown: normalized newlines, indentation dropped, a leading block
    /// marker escaped on every line, and the user's line breaks kept as hard breaks (two trailing
    /// spaces) inside a paragraph. `firstLinePrefix` is our own text before the first line, which
    /// already keeps that line from opening a block. `linePrefix` repeats on every line.
    private static func escapedBlock(_ text: String, firstLinePrefix: String = "", linePrefix: String = "") -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.enumerated().map { index, line in
            let escaped = (index == 0 && !firstLinePrefix.isEmpty) ? line : escapedLeadingMarker(line)
            let hasNext = index + 1 < lines.count && !lines[index + 1].isEmpty
            let hardBreak = !line.isEmpty && hasNext ? "  " : ""
            let prefix = (index == 0 ? firstLinePrefix : "") + linePrefix
            return line.isEmpty ? prefix.trimmingCharacters(in: .whitespaces) : prefix + escaped + hardBreak
        }.joined(separator: "\n")
    }
}

/// The per-book Markdown export. Cheap to construct, because a `ShareLink` in a view body builds
/// it on every pass: it holds only the book's identifier and the container. The moments are read,
/// sorted and rendered on the main actor inside the transfer closure, when the user shares, and
/// the export date is the time of sharing.
struct MomentsMarkdownExport: Transferable, Sendable {
    let bookID: PersistentIdentifier
    let container: ModelContainer
    let bookTitle: String
    /// Fixed date for tests; `nil` means the moment of sharing.
    let exportDate: Date?

    var suggestedFilename: String { Self.filename(forBookTitle: bookTitle) }

    static func filename(forBookTitle title: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // A leading dot would make the shared file hidden.
            .drop(while: { $0 == "." || $0.isWhitespace })
        let base = sanitized.isEmpty ? "Book" : String(sanitized)
        return "\(base) Moments.md"
    }

    init(book: Audiobook, container: ModelContainer, exportDate: Date? = nil) {
        self.bookID = book.persistentModelID
        self.container = container
        self.bookTitle = book.title
        self.exportDate = exportDate
    }

    /// Reads the book fresh from the main context and renders it. Main actor: SwiftData models
    /// belong to the context's actor.
    @MainActor
    func renderMarkdown() throws -> String {
        guard let book = container.mainContext.existingModel(Audiobook.self, id: bookID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return MomentMarkdownExporter.markdown(for: book, exportDate: exportDate ?? .now)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType("net.daringfireball.markdown") ?? .plainText) { item in
            Data(try await item.renderMarkdown().utf8)
        }
        .suggestedFileName { item in
            item.suggestedFilename
        }
    }
}
