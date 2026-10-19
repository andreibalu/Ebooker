//
//  AIPassageContext.swift
//  Pageless
//

import Foundation

/// Where a transcribed passage comes from. The prompt names the book so the model reads the
/// passage as published literature, which keeps its replies factual and its refusals rare.
struct AIPassageContext: Sendable, Equatable {
    var bookTitle: String
    var author: String = ""
    var chapterTitle: String?

    /// The header lines above the passage in every prompt.
    var promptHeader: String {
        var lines: [String] = []
        let title = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            lines.append(author.isEmpty ? "Book: \(title)" : "Book: \(title) by \(author)")
        }
        if let chapter = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !chapter.isEmpty {
            lines.append("Chapter: \(chapter)")
        }
        return lines.joined(separator: "\n")
    }

    func prompt(passage: String) -> String {
        let header = promptHeader
        return (header.isEmpty ? "" : header + "\n\n") + "Passage:\n" + passage
    }
}
