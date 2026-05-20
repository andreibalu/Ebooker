//
//  ReadingSession.swift
//  Pageless
//

import Foundation
import SwiftData

/// A single chunk of listening time attributed to one audiobook, bucketed by wall-clock hour.
///
/// Sessions are emitted by `ReadingSessionRecorder` during playback (one per ~5 minutes of
/// continuous play, or whenever playback pauses, switches book, or the app backgrounds).
/// They drive the Reading Activity heatmap and stats screen.
///
/// Book metadata is snapshotted so stats remain accurate after a book is removed.
@Model
final class ReadingSession {
    @Attribute(.unique) var id: UUID

    /// Start-of-day in the user's calendar. Stable per-day index for the heatmap.
    var date: Date
    /// "YYYY-MM-DD" for fast grouping/lookups without recomputing calendar components.
    var dayKey: String
    /// 0...23, wall-clock hour when the chunk began.
    var hour: Int
    /// Wall-clock minutes listened in this chunk (≥1).
    var minutes: Int

    var bookID: UUID
    var bookTitle: String
    var bookAuthor: String
    var isFreeBook: Bool

    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        dayKey: String,
        hour: Int,
        minutes: Int,
        bookID: UUID,
        bookTitle: String,
        bookAuthor: String,
        isFreeBook: Bool,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.dayKey = dayKey
        self.hour = hour
        self.minutes = minutes
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.isFreeBook = isFreeBook
        self.createdAt = createdAt
    }

    static func makeDayKey(date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
