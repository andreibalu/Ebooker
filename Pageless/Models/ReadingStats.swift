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

    let totalMinutes: Int
    let totalSessions: Int
    let avgSession: Double            // minutes / session
    let bestDay: BestDay?
    let bestHour: Int                 // 0...23
    let bestDow: Int                  // 0...6  (Mon = 0)
    let hourMinutes: [Int]            // count 24
    let dowMinutes: [Int]             // count 7  (Mon = 0)
    let currentStreak: Int
    let longestStreak: Int
    let booksFinished: Int
    let topAuthor: String?
    let topAuthorMinutes: Int
    let bookMinutes: [UUID: Int]
    let longestBookID: UUID?
    let longestBookTitle: String?
    let longestBookAuthor: String?
    let longestBookMinutes: Int
    let freeMinutes: Int
    let freePct: Double               // 0...1
    let activityByDay: [String: ReadingDayActivity]
    let firstDay: Date                // start-of-day of earliest session, or `today` if none
    let today: Date                   // start-of-day "today"
    let daysTracked: Int              // (today - firstDay) + 1, ≥ 1

    var hasAnyActivity: Bool { totalSessions > 0 }

    static let empty: ReadingStats = ReadingStats(
        totalMinutes: 0,
        totalSessions: 0,
        avgSession: 0,
        bestDay: nil,
        bestHour: 0,
        bestDow: 0,
        hourMinutes: Array(repeating: 0, count: 24),
        dowMinutes: Array(repeating: 0, count: 7),
        currentStreak: 0,
        longestStreak: 0,
        booksFinished: 0,
        topAuthor: nil,
        topAuthorMinutes: 0,
        bookMinutes: [:],
        longestBookID: nil,
        longestBookTitle: nil,
        longestBookAuthor: nil,
        longestBookMinutes: 0,
        freeMinutes: 0,
        freePct: 0,
        activityByDay: [:],
        firstDay: Calendar.current.startOfDay(for: .now),
        today: Calendar.current.startOfDay(for: .now),
        daysTracked: 1
    )

    static func compute(
        sessions: [ReadingSession],
        booksFinished: Int,
        today refDate: Date = .now,
        calendar: Calendar = .current
    ) -> ReadingStats {
        let today = calendar.startOfDay(for: refDate)

        guard !sessions.isEmpty else {
            return ReadingStats.empty
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

        for s in sessions {
            totalMinutes += s.minutes
            if s.isFreeBook { freeMinutes += s.minutes }

            if s.hour >= 0 && s.hour < 24 { hourMinutes[s.hour] += s.minutes }

            // Mon = 0, Sun = 6
            let weekday = calendar.component(.weekday, from: s.date) // 1 = Sunday
            let mondayFirst = (weekday + 5) % 7
            dowMinutes[mondayFirst] += s.minutes

            bookMinutes[s.bookID, default: 0] += s.minutes
            if bookTitleByID[s.bookID] == nil { bookTitleByID[s.bookID] = s.bookTitle }
            if bookAuthorByID[s.bookID] == nil { bookAuthorByID[s.bookID] = s.bookAuthor }

            minutesByDay[s.dayKey, default: 0] += s.minutes
            bookByDay[s.dayKey, default: [:]][s.bookID, default: 0] += s.minutes
            dateByDayKey[s.dayKey] = s.date

            if s.date < earliest { earliest = s.date }
        }

        // Per-day aggregate + best day
        var activityByDay: [String: ReadingDayActivity] = [:]
        var bestDay: BestDay? = nil
        for (dayKey, minutes) in minutesByDay {
            let date = dateByDayKey[dayKey] ?? today
            var top: UUID? = nil
            var topMin = 0
            for (bid, mm) in bookByDay[dayKey] ?? [:] where mm > topMin {
                top = bid
                topMin = mm
            }
            activityByDay[dayKey] = ReadingDayActivity(
                dayKey: dayKey,
                date: date,
                minutes: minutes,
                topBookID: top
            )
            if bestDay == nil || minutes > (bestDay?.minutes ?? 0) {
                bestDay = BestDay(
                    date: date,
                    dayKey: dayKey,
                    minutes: minutes,
                    topBookID: top,
                    topBookTitle: top.flatMap { bookTitleByID[$0] },
                    topBookAuthor: top.flatMap { bookAuthorByID[$0] }
                )
            }
        }

        // Peak hour / dow
        var bestHour = 0
        for h in 0..<24 where hourMinutes[h] > hourMinutes[bestHour] { bestHour = h }
        var bestDow = 0
        for d in 0..<7 where dowMinutes[d] > dowMinutes[bestDow] { bestDow = d }

        // Longest book + top author by minutes
        var longestBookID: UUID? = nil
        var longestBookMins = 0
        for (id, mm) in bookMinutes where mm > longestBookMins {
            longestBookID = id
            longestBookMins = mm
        }
        var authorMinutes: [String: Int] = [:]
        for (id, mm) in bookMinutes {
            if let author = bookAuthorByID[id], !author.isEmpty {
                authorMinutes[author, default: 0] += mm
            }
        }
        var topAuthor: String? = nil
        var topAuthorMins = 0
        for (a, mm) in authorMinutes where mm > topAuthorMins {
            topAuthor = a
            topAuthorMins = mm
        }

        // Streaks (today backwards for current; full scan for longest)
        let firstDay = calendar.startOfDay(for: earliest)
        let daysTracked = max(1, (calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1)

        var currentStreak = 0
        for offset in 0..<daysTracked {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            let key = ReadingSession.makeDayKey(date: d, calendar: calendar)
            if activityByDay[key] != nil { currentStreak += 1 } else { break }
        }
        var longestStreak = 0
        var run = 0
        for offset in 0..<daysTracked {
            guard let d = calendar.date(byAdding: .day, value: -(daysTracked - 1 - offset), to: today) else { continue }
            let key = ReadingSession.makeDayKey(date: d, calendar: calendar)
            if activityByDay[key] != nil { run += 1; longestStreak = max(longestStreak, run) } else { run = 0 }
        }

        let totalSessions = sessions.count
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
            longestStreak: longestStreak,
            booksFinished: booksFinished,
            topAuthor: topAuthor,
            topAuthorMinutes: topAuthorMins,
            bookMinutes: bookMinutes,
            longestBookID: longestBookID,
            longestBookTitle: longestBookID.flatMap { bookTitleByID[$0] },
            longestBookAuthor: longestBookID.flatMap { bookAuthorByID[$0] },
            longestBookMinutes: longestBookMins,
            freeMinutes: freeMinutes,
            freePct: totalMinutes > 0 ? Double(freeMinutes) / Double(totalMinutes) : 0,
            activityByDay: activityByDay,
            firstDay: firstDay,
            today: today,
            daysTracked: daysTracked
        )
    }
}
