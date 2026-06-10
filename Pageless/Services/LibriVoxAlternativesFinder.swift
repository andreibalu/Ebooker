//
//  LibriVoxAlternativesFinder.swift
//  Pageless
//

import Foundation
import SwiftData

/// Finds alternative LibriVox recordings of the same text ("Other Recordings").
///
/// LibriVox names re-recordings with trailing parenthetical suffixes — "(version 2)",
/// "(dramatic reading)", "(abridged)" — so grouping strips only those *known* suffixes.
/// Unknown parentheticals (translations, subtitles) are kept: "The Iliad (Pope
/// Translation)" and "(Butler Translation)" are different texts and must never merge.
/// Matching is local-only against the cached `LibriVoxBook` catalog: same author,
/// same language, same normalized title.
enum LibriVoxAlternativesFinder {

    /// Known LibriVox re-recording suffixes. Deliberately conservative — extend only
    /// with suffixes that mark a re-recording of the *same* text.
    private static let suffixAlternation =
        #"(?:version\s*\d+(?:\s+dramatic\s+reading)?|dramatic\s+reading|abridged|unabridged|solo|group)"#

    private static let trailingSuffixRegex = try! NSRegularExpression(
        pattern: #"\s*\((\#(suffixAlternation))\)\s*$"#,
        options: [.caseInsensitive]
    )

    /// Canonical grouping key: known suffixes stripped (repeatedly, for stacked ones),
    /// case + diacritics folded, whitespace collapsed.
    static func normalizedTitleKey(_ title: String) -> String {
        var stripped = title
        while true {
            let range = NSRange(stripped.startIndex..., in: stripped)
            let next = trailingSuffixRegex.stringByReplacingMatches(
                in: stripped, options: [], range: range, withTemplate: ""
            )
            if next == stripped { break }
            stripped = next
        }
        let folded = stripped.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Human-readable badge for a recording's trailing suffix — "Version 2",
    /// "Dramatic Reading" — or nil when the title carries no known suffix (the original).
    static func versionLabel(_ title: String) -> String? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = trailingSuffixRegex.firstMatch(in: title, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: title) else { return nil }
        let inner = title[captureRange].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return inner.lowercased().capitalized
    }

    /// All other recordings of `book`'s text in the cached catalog: same author and
    /// language (narrowed via predicate), same normalized title, excluding `book` itself.
    /// Sorted original first, then "(version N)" ascending, then other readings.
    static func alternatives(to book: LibriVoxBook, context: ModelContext) -> [LibriVoxBook] {
        let language = book.language
        let author = book.authorDisplay
        let descriptor = FetchDescriptor<LibriVoxBook>(
            predicate: #Predicate { $0.language == language && $0.authorDisplay == author }
        )
        guard let candidates = try? context.fetch(descriptor) else { return [] }
        let key = normalizedTitleKey(book.title)
        let bookID = book.id
        return candidates
            .filter { $0.id != bookID && normalizedTitleKey($0.title) == key }
            .sorted { sortKey(for: $0) < sortKey(for: $1) }
    }

    /// (rank, version number, title): original = 0, "(version N)" = 1 ordered by N,
    /// other known suffixes (dramatic readings etc.) = 2.
    private static func sortKey(for book: LibriVoxBook) -> (Int, Int, String) {
        guard let label = versionLabel(book.title) else { return (0, 0, book.title) }
        let lowered = label.lowercased()
        if lowered.hasPrefix("version") {
            let digits = lowered.drop { !$0.isNumber }.prefix { $0.isNumber }
            return (1, Int(digits) ?? 0, book.title)
        }
        return (2, 0, book.title)
    }
}
