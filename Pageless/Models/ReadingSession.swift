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
/// They drive the Reading Activity heatmap and stats screen. A row is a *chunk*, not a sitting:
/// `ReadingStats.compute` coalesces chunks into logical sessions from the columns below, so this
/// model carries no session id (and no CloudKit schema change).
///
/// Book metadata is snapshotted so stats remain accurate after a book is removed.
@Model
final class ReadingSession {
    // CloudKit-backed SwiftData stores cannot declare @Attribute(.unique);
    // app-level UUID uniqueness is enforced by `id` semantics.
    var id: UUID = UUID()

    /// Start-of-day in the user's calendar. Stable per-day index for the heatmap.
    var date: Date = Date.distantPast
    /// "YYYY-MM-DD" for fast grouping/lookups without recomputing calendar components.
    var dayKey: String = ""
    /// 0...23, wall-clock hour when the chunk began.
    var hour: Int = 0
    /// Wall-clock minutes listened in this chunk (≥1).
    var minutes: Int = 0

    var bookID: UUID = UUID()
    var bookTitle: String = ""
    var bookAuthor: String = ""
    var isFreeBook: Bool = false

    /// When the chunk ended (the recorder stamps it at flush), so `createdAt − minutes` estimates its
    /// start. `ReadingStats` trusts it only when that estimate lies near `date` + `hour`; `.distantPast`
    /// (rows from before the column, or hand-built ones) falls back to hour grouping.
    var createdAt: Date = Date.distantPast

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
