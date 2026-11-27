//
//  MomentQuoteText.swift
//  Pageless
//

import Foundation

/// One normalization for a moment's quote, shared by the book-page row and the share card.
/// A stored quote may already carry its own quote marks (AI output, or typed by the user), and
/// both surfaces add typographic marks of their own, so the marks are stripped first.
/// Only double marks go: a trailing single mark is usually an apostrophe ("the dogs'").
enum MomentQuoteText {
    private static let marks = CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{201E}\u{201F}")

    /// The quote without surrounding whitespace or double quote marks, or `nil` when nothing is left.
    static func stripped(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let boundary = marks.union(.whitespacesAndNewlines)
        let result = raw.trimmingCharacters(in: boundary)
        return result.isEmpty ? nil : result
    }

    /// The quote wrapped in one pair of curly quotes, or `nil` when nothing is left to show.
    static func decorated(_ raw: String?) -> String? {
        stripped(raw).map { "\u{201C}\($0)\u{201D}" }
    }
}
