//
//  ReadingStats.swift
//  Pageless
//

import Foundation

/// Per-day aggregate used to drive the heatmap and to pick "best day".
struct ReadingDayActivity: Equatable {
    let dayKey: String
    let date: Date
    let minutes: Int
    let topBookID: UUID?
    /// Title snapshot of `topBookID`, for the day-detail summary.
    let topBookTitle: String?
}

/// Derived snapshot of all `ReadingSession` rows. Recomputed when the underlying query changes.
///
/// Mirrors the `READING_STATS` block in the JS prototype.
struct ReadingStats: Equatable {
    struct BestDay: Equatable {
        let date: Date
        let dayKey: String
        let minutes: Int
        let topBookID: UUID?
        let topBookTitle: String?
        let topBookAuthor: String?
    }

    /// One book's listening total. `topBooks` sorts these by `ranksBefore`.
    struct BookTotal: Equatable, Identifiable {
        let id: UUID
        let title: String
        let author: String
        let minutes: Int

        /// Minutes descending, then title, then id, so equal totals never reorder between recomputes.
        func ranksBefore(_ other: BookTotal) -> Bool {
            if minutes != other.minutes { return minutes > other.minutes }
            if title != other.title { return title < other.title }
            return id.uuidString < other.id.uuidString
        }
    }

    let totalMinutes: Int
    /// Logical listening sessions: contiguous `ReadingSession` chunks coalesced (see `compute`).
    let totalSessions: Int
    let avgSession: Double            // minutes / logical session
    let bestDay: BestDay?
    let bestHour: Int                 // 0...23
    let bestDow: Int                  // 0...6  (Mon = 0)
    let hourMinutes: [Int]            // count 24
    let dowMinutes: [Int]             // count 7  (Mon = 0)
    /// Consecutive days with activity ending today, or ending yesterday while today is still empty.
    let currentStreak: Int
    /// True when today (or a day later than today, after westward time-zone travel) has activity.
    let isStreakActiveToday: Bool
    let longestStreak: Int
    let booksFinished: Int
    let topAuthor: String?
    let topAuthorMinutes: Int
    let bookMinutes: [UUID: Int]
    /// Every listened book, most minutes first. `longestBook*` is its first element.
    let topBooks: [BookTotal]
    let longestBookID: UUID?
    let longestBookTitle: String?
    let longestBookAuthor: String?
    let longestBookMinutes: Int
    let freeMinutes: Int
    let freePct: Double               // 0...1
    let activityByDay: [String: ReadingDayActivity]
    /// Minutes recorded today. Lags by up to the recorder's unflushed chunk (≤5 min).
    let todayMinutes: Int
    let firstDay: Date                // start-of-day of earliest session, or `today` if none
    let today: Date                   // start-of-day "today"
    let daysTracked: Int              // (today - firstDay) + 1, ≥ 1

    var hasAnyActivity: Bool { totalSessions > 0 }

    static var empty: ReadingStats { empty() }

    static func empty(today refDate: Date = .now, calendar: Calendar = .current) -> ReadingStats {
        let today = calendar.startOfDay(for: refDate)
        return ReadingStats(
            totalMinutes: 0,
            totalSessions: 0,
            avgSession: 0,
            bestDay: nil,
            bestHour: 0,
            bestDow: 0,
            hourMinutes: Array(repeating: 0, count: 24),
            dowMinutes: Array(repeating: 0, count: 7),
            currentStreak: 0,
            isStreakActiveToday: false,
            longestStreak: 0,
            booksFinished: 0,
            topAuthor: nil,
            topAuthorMinutes: 0,
            bookMinutes: [:],
            topBooks: [],
            longestBookID: nil,
            longestBookTitle: nil,
            longestBookAuthor: nil,
            longestBookMinutes: 0,
            freeMinutes: 0,
            freePct: 0,
            activityByDay: [:],
            todayMinutes: 0,
            firstDay: today,
            today: today,
            daysTracked: 1
        )
    }

    /// Chunk rows within this many minutes of their hour bucket count as timed (see `logicalSessionCount`).
    private static let timedToleranceSeconds: TimeInterval = 75 * 60
    /// Slack added to twice a chunk's length when deciding whether it continues the previous chunk.
    private static let joinSlackSeconds: TimeInterval = 180

    static func compute(
        sessions: [ReadingSession],
        booksFinished: Int,
        today refDate: Date = .now,
        calendar: Calendar = .current
    ) -> ReadingStats {
        let today = calendar.startOfDay(for: refDate)

        guard !sessions.isEmpty else {
            return empty(today: refDate, calendar: calendar)
        }

        var totalMinutes = 0
        var freeMinutes = 0
        var hourMinutes = Array(repeating: 0, count: 24)
        var dowMinutes = Array(repeating: 0, count: 7)
        var bookMinutes: [UUID: Int] = [:]
        var bookTitleByID: [UUID: String] = [:]
        var bookAuthorByID: [UUID: String] = [:]
        var minutesByDay: [String: Int] = [:]
        var bookByDay: [String: [UUID: Int]] = [:]
        var dateByDayKey: [String: Date] = [:]
        var earliest: Date = today

        // Ascending by (createdAt, id): the latest title snapshot of a book wins, whatever the input order.
        let ordered = sessions.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        for s in ordered {
            totalMinutes += s.minutes
            if s.isFreeBook { freeMinutes += s.minutes }

            if s.hour >= 0 && s.hour < 24 { hourMinutes[s.hour] += s.minutes }

            // Mon = 0, Sun = 6
            let weekday = calendar.component(.weekday, from: s.date) // 1 = Sunday
            let mondayFirst = (weekday + 5) % 7
            dowMinutes[mondayFirst] += s.minutes

            bookMinutes[s.bookID, default: 0] += s.minutes
            bookTitleByID[s.bookID] = s.bookTitle
            bookAuthorByID[s.bookID] = s.bookAuthor

            minutesByDay[s.dayKey, default: 0] += s.minutes
            bookByDay[s.dayKey, default: [:]][s.bookID, default: 0] += s.minutes
            dateByDayKey[s.dayKey] = s.date

            if s.date < earliest { earliest = s.date }
        }

        func bookTotal(_ id: UUID, _ minutes: Int) -> BookTotal {
            BookTotal(id: id, title: bookTitleByID[id] ?? "", author: bookAuthorByID[id] ?? "", minutes: minutes)
        }

        // Per-day aggregate + best day
        var activityByDay: [String: ReadingDayActivity] = [:]
        for (dayKey, minutes) in minutesByDay {
            let date = dateByDayKey[dayKey] ?? today
            let top = (bookByDay[dayKey] ?? [:])
                .map { bookTotal($0.key, $0.value) }
                .min { $0.ranksBefore($1) }
            activityByDay[dayKey] = ReadingDayActivity(
                dayKey: dayKey,
                date: date,
                minutes: minutes,
                topBookID: top?.id,
                topBookTitle: top?.title
            )
        }
        // Most minutes wins; equal days go to the earlier date.
        var bestDay: BestDay? = nil
        if let best = activityByDay.values.min(by: {
            $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.dayKey < $1.dayKey
        }) {
            bestDay = BestDay(
                date: best.date,
                dayKey: best.dayKey,
                minutes: best.minutes,
                topBookID: best.topBookID,
                topBookTitle: best.topBookID.flatMap { bookTitleByID[$0] },
                topBookAuthor: best.topBookID.flatMap { bookAuthorByID[$0] }
            )
        }

        // Peak hour / dow
        var bestHour = 0
        for h in 0..<24 where hourMinutes[h] > hourMinutes[bestHour] { bestHour = h }
        var bestDow = 0
        for d in 0..<7 where dowMinutes[d] > dowMinutes[bestDow] { bestDow = d }

        // Books by minutes, then top author (ties go to the alphabetically first name)
        let topBooks = bookMinutes
            .map { bookTotal($0.key, $0.value) }
            .sorted { $0.ranksBefore($1) }
        let longest = topBooks.first
        var authorMinutes: [String: Int] = [:]
        for book in topBooks where !book.author.isEmpty {
            authorMinutes[book.author, default: 0] += book.minutes
        }
        let topAuthorEntry = authorMinutes.min {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }

        let firstDay = calendar.startOfDay(for: earliest)
        let daysTracked = max(1, (calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1)

        // A dayKey later than today (time zone travel west) counts as today.
        let todayKey = ReadingSession.makeDayKey(date: today, calendar: calendar)
        let futureKeys = activityByDay.keys.filter { $0 > todayKey }
        let isActiveToday = activityByDay[todayKey] != nil || !futureKeys.isEmpty
        let todayMinutes = (activityByDay[todayKey]?.minutes ?? 0)
            + futureKeys.reduce(0) { $0 + (activityByDay[$1]?.minutes ?? 0) }

        // Current streak: back from today, or from yesterday while today is still empty. The walk
        // ends at the first empty day, so it needs no bound.
        var currentStreak = 0
        var offset = isActiveToday ? 0 : 1
        while let d = calendar.date(byAdding: .day, value: -offset, to: today) {
            let present = offset == 0
                ? isActiveToday
                : activityByDay[ReadingSession.makeDayKey(date: d, calendar: calendar)] != nil
            guard present else { break }
            currentStreak += 1
            offset += 1
        }

        var longestStreak = 0
        var run = 0
        for offset in 0..<daysTracked {
            guard let d = calendar.date(byAdding: .day, value: -(daysTracked - 1 - offset), to: today) else { continue }
            let key = ReadingSession.makeDayKey(date: d, calendar: calendar)
            if activityByDay[key] != nil { run += 1; longestStreak = max(longestStreak, run) } else { run = 0 }
        }
        // A future-keyed day is outside the scan above but inside the current streak.
        longestStreak = max(longestStreak, currentStreak)

        let totalSessions = logicalSessionCount(sessions, calendar: calendar)
        let avgSession = totalSessions > 0 ? Double(totalMinutes) / Double(totalSessions) : 0

        return ReadingStats(
            totalMinutes: totalMinutes,
            totalSessions: totalSessions,
            avgSession: avgSession,
            bestDay: bestDay,
            bestHour: bestHour,
            bestDow: bestDow,
            hourMinutes: hourMinutes,
            dowMinutes: dowMinutes,
            currentStreak: currentStreak,
            isStreakActiveToday: isActiveToday,
            longestStreak: longestStreak,
            booksFinished: booksFinished,
            topAuthor: topAuthorEntry?.key,
            topAuthorMinutes: topAuthorEntry?.value ?? 0,
            bookMinutes: bookMinutes,
            topBooks: topBooks,
            longestBookID: longest?.id,
            longestBookTitle: longest?.title,
            longestBookAuthor: longest?.author,
            longestBookMinutes: longest?.minutes ?? 0,
            freeMinutes: freeMinutes,
            freePct: totalMinutes > 0 ? Double(freeMinutes) / Double(totalMinutes) : 0,
            activityByDay: activityByDay,
            todayMinutes: todayMinutes,
            firstDay: firstDay,
            today: today,
            daysTracked: daysTracked
        )
    }

    /// Coalesces the recorder's chunk rows into logical listening sessions. No stored session id:
    /// the rule reads only existing columns, so the synced schema is unchanged.
    ///
    /// A row is *timed* when `createdAt` is set and its estimated start (`createdAt` − minutes) lies
    /// within 75 minutes of its bucket instant (`date` + `hour`). Timed rows sort by `createdAt`, and a
    /// row joins the previous one when it is the same book and arrived within twice its own length plus
    /// 3 minutes (a wide enough window for old rows credited in book time at 0.5x to 3x, rounding, and
    /// dropped sub-30 s chunks). *Untimed* rows sort by (dayKey, book, hour), so another book's row in
    /// the same hour can't split a book's run, and join the previous one when it is the same book, the
    /// same day and the same or the next hour. The two kinds never join.
    private static func logicalSessionCount(_ sessions: [ReadingSession], calendar: Calendar) -> Int {
        var timed: [ReadingSession] = []
        var untimed: [ReadingSession] = []
        for s in sessions {
            // The bucket's wall-clock hour on its day, not `date + hour * 3600` and not
            // `date(byAdding: .hour)`: both add elapsed time, so on a DST day they land an hour off
            // and can push a real chunk outside the tolerance.
            let bucketInstant = calendar.date(bySettingHour: s.hour, minute: 0, second: 0, of: s.date)
                ?? s.date.addingTimeInterval(Double(s.hour) * 3600)
            let estimatedStart = s.createdAt.addingTimeInterval(-Double(s.minutes) * 60)
            let isTimed = s.createdAt != .distantPast
                && abs(estimatedStart.timeIntervalSince(bucketInstant)) <= timedToleranceSeconds
            if isTimed { timed.append(s) } else { untimed.append(s) }
        }

        var count = 0
        var previous: ReadingSession?
        for s in timed.sorted(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }) {
            defer { previous = s }
            if let p = previous,
               p.bookID == s.bookID,
               s.createdAt.timeIntervalSince(p.createdAt) <= 2 * Double(s.minutes) * 60 + joinSlackSeconds {
                continue
            }
            count += 1
        }

        previous = nil
        for s in untimed.sorted(by: {
            ($0.dayKey, $0.bookID.uuidString, $0.hour, $0.id.uuidString)
                < ($1.dayKey, $1.bookID.uuidString, $1.hour, $1.id.uuidString)
        }) {
            defer { previous = s }
            if let p = previous,
               p.bookID == s.bookID,
               p.dayKey == s.dayKey,
               (0...1).contains(s.hour - p.hour) {
                continue
            }
            count += 1
        }
        return count
    }
}
