//
//  MomentSearch.swift
//  Pageless
//
//  Created for Slice 02: Moments Transcripts, Inline Metadata & Quote Sharing.
//

import Foundation
import SwiftUI

@MainActor
enum MomentSearch {
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func score(_ moment: Moment, words: [String]) -> Int? {
        guard let book = moment.audiobook else { return nil }
        let titles = fold([moment.label, book.title, book.author].joined(separator: " "))
        let prose = fold([moment.notes ?? "", moment.quoteLine ?? ""].joined(separator: " "))
        let metadata = fold((moment.characters + moment.categories.map(\.displayName)
                            + [moment.mood?.displayName].compactMap { $0 }).joined(separator: " "))
        let transcript = fold(moment.transcript ?? "")
        guard words.allSatisfy({
            titles.contains($0) || prose.contains($0) || metadata.contains($0) || transcript.contains($0)
        }) else { return nil }
        return words.reduce(0) {
            $0 + (titles.contains($1) ? 10 : prose.contains($1) ? 2 : transcript.contains($1) ? 1 : 0)
        }
    }

    static func highlighted(_ value: String, query: String) -> AttributedString {
        var result = AttributedString(value)
        for word in words(query) {
            var start = value.startIndex
            while start < value.endIndex,
                  let range = value.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                          range: start..<value.endIndex, locale: .current) {
                if let lower = AttributedString.Index(range.lowerBound, within: result),
                   let upper = AttributedString.Index(range.upperBound, within: result) {
                    result[lower..<upper].backgroundColor = Color.amber.opacity(0.25)
                }
                start = range.upperBound
            }
        }
        return result
    }

    /// Returns a compact snippet around the first transcript-only match, or `nil` if every
    /// matching query word already appears in the row's visible text.
    static func transcriptSnippet(for moment: Moment, query: String) -> String? {
        let queryWords = words(query)
        guard !queryWords.isEmpty, let transcript = moment.transcript, !transcript.isEmpty else { return nil }

        let visibleParts = [moment.label, moment.notes ?? "", moment.quoteLine ?? ""]
            + moment.characters
            + moment.categories.map(\.displayName)
            + [moment.mood?.displayName].compactMap { $0 }
        let visible = fold(visibleParts.joined(separator: " "))
        let foldedTranscript = fold(transcript)

        let transcriptOnlyWords = queryWords.filter { !visible.contains($0) && foldedTranscript.contains($0) }
        guard !transcriptOnlyWords.isEmpty else { return nil }

        return transcriptSnippet(transcript, words: transcriptOnlyWords)
    }

    /// Pure windowing helper: centers up to `radius` words on each side of the first match
    /// among pre-folded `words`, adding leading/trailing `"…"` when text is truncated.
    static func transcriptSnippet(_ transcript: String, words: [String], radius: Int = 8) -> String? {
        guard !words.isEmpty else { return nil }
        let tokens = transcript.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return nil }

        guard let matchIndex = tokens.firstIndex(where: { token in
            let foldedToken = fold(String(token))
            return words.contains(where: { foldedToken.contains($0) })
        }) else {
            return nil
        }

        let safeRadius = max(0, radius)
        let startIndex = max(0, matchIndex - safeRadius)
        let endIndex = min(tokens.count - 1, matchIndex + safeRadius)
        let window = tokens[startIndex...endIndex].joined(separator: " ")

        return (startIndex > 0 ? "…" : "") + window + (endIndex < tokens.count - 1 ? "…" : "")
    }
}
