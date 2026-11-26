import Foundation
import Testing
@testable import Pageless

/// Pure `ReadingStats.compute` math (slice 01, D1–D3). Every test uses a fixed UTC calendar so the
/// result never depends on the machine's time zone.
struct ReadingStatsTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var cal: Calendar { Self.calendar }

    /// "Now" is 2026-11-26 12:00 UTC; `today` start-of-day is 00:00 of that date.
    private var now: Date { at(2026, 11, 26, 12, 0) }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private func day(_ offsetFromToday: Int) -> Date {
        cal.date(byAdding: .day, value: offsetFromToday, to: cal.startOfDay(for: now))!
    }

    private let bookA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let bookB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    /// A timed row: `createdAt` is when the chunk ended, as the recorder stamps it.
    private func timed(
        start: Date,
        minutes: Int,
        book: UUID? = nil,
        title: String = "A",
        author: String = "Author",
        free: Bool = false,
        createdAt: Date? = nil
    ) -> ReadingSession {
        let startOfDay = cal.startOfDay(for: start)
        return ReadingSession(
            date: startOfDay,
            dayKey: ReadingSession.makeDayKey(date: startOfDay, calendar: cal),
            hour: cal.component(.hour, from: start),
            minutes: minutes,
            bookID: book ?? bookA,
            bookTitle: title,
            bookAuthor: author,
            isFreeBook: free,
            createdAt: createdAt ?? start.addingTimeInterval(Double(minutes) * 60)
        )
    }

    /// A row with no usable timestamp (`createdAt == .distantPast`), as old rows or hand-built ones.
    private func untimed(
        dayOffset: Int,
        hour: Int,
        minutes: Int,
        book: UUID? = nil,
        title: String = "A"
    ) -> ReadingSession {
        let d = day(dayOffset)
        return ReadingSession(
            date: d,
            dayKey: ReadingSession.makeDayKey(date: d, calendar: cal),
            hour: hour,
            minutes: minutes,
            bookID: book ?? bookA,
            bookTitle: title,
            bookAuthor: "Author",
            isFreeBook: false,
            createdAt: .distantPast
        )
    }

    private func compute(_ sessions: [ReadingSession]) -> ReadingStats {
        ReadingStats.compute(sessions: sessions, booksFinished: 0, today: now, calendar: cal)
    }

    /// One row on `offset` days from today at 20:00, enough to mark the day active.
    private func active(_ offset: Int) -> ReadingSession {
        timed(start: cal.date(byAdding: .hour, value: 20, to: day(offset))!, minutes: 10)
    }

    // MARK: Session coalescing

    @Test func twelveFiveMinuteChunksAreOneSixtyMinuteSession() {
        // Catches the 5-minute average cap: twelve chunk rows must count as one sitting.
        let start = at(2026, 11, 25, 20, 0)
        let rows = (0..<12).map { timed(start: start.addingTimeInterval(Double($0) * 300), minutes: 5) }
        let stats = compute(rows)
        #expect(stats.totalSessions == 1)
        #expect(stats.avgSession == 60)
        #expect(stats.totalMinutes == 60)
    }

    @Test func oldBookTimeChunksAtHalfAndTripleSpeedStillMerge() {
        // Catches the gap tolerance being too tight for pre-fix rows credited in book time (0.5x / 3x).
        let start = at(2026, 11, 25, 20, 0)
        // 0.5x: 5 credited minutes took 10 real minutes. 3x: they took 100 seconds.
        for spacing in [600.0, 100.0] {
            let rows = (0..<4).map { i -> ReadingSession in
                let end = start.addingTimeInterval(Double(i + 1) * spacing)
                return timed(start: start, minutes: 5, createdAt: end)
            }
            #expect(compute(rows).totalSessions == 1, "spacing \(spacing)")
        }
    }

    @Test func gapBeyondToleranceSplitsSessions() {
        // Catches two separate sittings of the same book being fused into one.
        let start = at(2026, 11, 25, 20, 0)
        let first = timed(start: start, minutes: 5)
        // Tolerance is 2 * minutes * 60 + 180 s = 780 s after the previous row's createdAt.
        let secondEnd = first.createdAt.addingTimeInterval(781)
        let second = timed(start: secondEnd.addingTimeInterval(-300), minutes: 5, createdAt: secondEnd)
        #expect(compute([first, second]).totalSessions == 2)

        let justInsideEnd = first.createdAt.addingTimeInterval(780)
        let inside = timed(start: justInsideEnd.addingTimeInterval(-300), minutes: 5, createdAt: justInsideEnd)
        #expect(compute([first, inside]).totalSessions == 1)
    }

    @Test func differentBooksNeverMerge() {
        // Catches back-to-back chunks of two books being counted as one sitting.
        let start = at(2026, 11, 25, 20, 0)
        let a = timed(start: start, minutes: 5, book: bookA)
        let b = timed(start: start.addingTimeInterval(300), minutes: 5, book: bookB, title: "B")
        let stats = compute([a, b])
        #expect(stats.totalSessions == 2)
        #expect(stats.avgSession == 5)
    }

    @Test func chunksAcrossMidnightMergeAndKeepTheirStartDay() {
        // Catches a sitting that crosses midnight splitting in two, or its minutes moving to the new day.
        let first = timed(start: at(2026, 11, 24, 23, 57), minutes: 5)
        let second = timed(start: at(2026, 11, 25, 0, 2), minutes: 5)
        let stats = compute([first, second])
        #expect(stats.totalSessions == 1)
        #expect(stats.avgSession == 10)
        #expect(stats.activityByDay["2026-11-24"]?.minutes == 5)
        #expect(stats.activityByDay["2026-11-25"]?.minutes == 5)
    }

    @Test func untimedRowsGroupByAdjacentHourSameBookSameDay() {
        // Catches rows without createdAt (old data, hand-made fixtures) not coalescing by hour.
        let rows = [
            untimed(dayOffset: -1, hour: 20, minutes: 30),
            untimed(dayOffset: -1, hour: 21, minutes: 30),
            untimed(dayOffset: -1, hour: 22, minutes: 30), // chain: +1 from the previous untimed row
            untimed(dayOffset: -1, hour: 22, minutes: 10, book: bookB, title: "B"), // other book
            untimed(dayOffset: 0, hour: 23, minutes: 20), // other day
        ]
        let stats = compute(rows)
        #expect(stats.totalSessions == 3)
        #expect(stats.avgSession == Double(120) / 3)
    }

    @Test func untimedRowsWithAnHourGapSplit() {
        // Catches hour 20 and hour 22 rows being fused although an empty hour separates them.
        let rows = [
            untimed(dayOffset: -1, hour: 20, minutes: 30),
            untimed(dayOffset: -1, hour: 22, minutes: 30),
        ]
        #expect(compute(rows).totalSessions == 2)
    }

    @Test func timedAndUntimedRowsNeverJoinEachOther() {
        // Catches mixing the two row kinds, whose ordering keys are not comparable.
        let t = timed(start: at(2026, 11, 25, 20, 0), minutes: 30)
        let u = untimed(dayOffset: -1, hour: 20, minutes: 30)
        #expect(compute([t, u]).totalSessions == 2)
    }

    @Test func rowWhoseCreatedAtDisagreesWithItsHourBucketIsUntimed() {
        // Catches trusting a createdAt far from the row's date/hour (restored, clock-skewed or edited rows).
        let d = day(-1)
        func row(hour: Int, createdAt: Date) -> ReadingSession {
            ReadingSession(
                date: d,
                dayKey: ReadingSession.makeDayKey(date: d, calendar: cal),
                hour: hour,
                minutes: 30,
                bookID: bookA,
                bookTitle: "A",
                bookAuthor: "Author",
                isFreeBook: false,
                createdAt: createdAt
            )
        }
        // Both claim hours 20 and 21 of yesterday, but createdAt is days later, so they group by hour: 1 session.
        let late1 = row(hour: 20, createdAt: day(5))
        let late2 = row(hour: 21, createdAt: day(5).addingTimeInterval(60))
        #expect(compute([late1, late2]).totalSessions == 1)
        // Same situation with hours 20 and 23: hour grouping splits them. Trusting createdAt would merge.
        let far1 = row(hour: 20, createdAt: day(5))
        let far2 = row(hour: 23, createdAt: day(5).addingTimeInterval(60))
        #expect(compute([far1, far2]).totalSessions == 2)
    }

    @Test func timedRowsHoursApartStaySeparate() {
        // Catches a morning and an evening sitting of the same book merging into one.
        let a = timed(start: at(2026, 11, 25, 8, 0), minutes: 30)
        let b = timed(start: at(2026, 11, 25, 20, 0), minutes: 30)
        let stats = compute([a, b])
        #expect(stats.totalSessions == 2)
        #expect(stats.avgSession == 30)
    }

    @Test func inputOrderDoesNotChangeTheResult() {
        // Catches coalescing that depends on the @Query's date-only ordering.
        let start = at(2026, 11, 25, 20, 0)
        var rows = (0..<12).map { timed(start: start.addingTimeInterval(Double($0) * 300), minutes: 5) }
        rows.append(untimed(dayOffset: -3, hour: 9, minutes: 20))
        rows.append(untimed(dayOffset: -3, hour: 10, minutes: 20))
        let expected = compute(rows)
        #expect(expected.totalSessions == 2)
        #expect(compute(rows.reversed()) == expected)
        #expect(compute(rows.shuffled()) == expected)
    }

    // MARK: Streaks

    @Test func streakCountsFromYesterdayWhenTodayIsEmpty() {
        // Catches the every-morning reset to 0 before the first listen of the day.
        let stats = compute([active(-3), active(-2), active(-1)])
        #expect(stats.currentStreak == 3)
        #expect(stats.isStreakActiveToday == false)
    }

    @Test func streakIncludesTodayWhenListenedToday() {
        // Catches losing today from the count, and the flag staying false once today is active.
        let stats = compute([active(-2), active(-1), active(0)])
        #expect(stats.currentStreak == 3)
        #expect(stats.isStreakActiveToday)
    }

    @Test func streakBreaksAfterTwoEmptyDays() {
        // Catches grace extending past one missed day.
        let stats = compute([active(-4), active(-3), active(-2)])
        #expect(stats.currentStreak == 0)
        #expect(stats.isStreakActiveToday == false)
    }

    @Test func yesterdayOnlyIsAStreakOfOne() {
        // Catches a listener whose only day is yesterday seeing 0 (a one-day history).
        let stats = compute([active(-1)])
        #expect(stats.currentStreak == 1)
        #expect(stats.isStreakActiveToday == false)
    }

    @Test func streakIsNotLimitedByDaysTracked() {
        // Catches a long streak being truncated by a loop bound.
        let rows = (-150...0).map { active($0) }
        let stats = compute(rows)
        #expect(stats.currentStreak == 151)
        #expect(stats.longestStreak == 151)
    }

    @Test func futureDayKeyCountsAsToday() {
        // Catches a row dated tomorrow (time zone travel west) being ignored or breaking the streak.
        let future = timed(start: cal.date(byAdding: .hour, value: 1, to: day(1))!, minutes: 10)
        let stats = compute([active(-1), future])
        #expect(stats.currentStreak == 2)
        #expect(stats.isStreakActiveToday)
        #expect(stats.longestStreak >= stats.currentStreak)
        #expect(stats.todayMinutes == 10)
    }

    @Test func onlyAFutureDayKeyIsAStreakOfOneActiveToday() {
        // Catches daysTracked == 1 with no row on today's key producing a 0 streak.
        let future = timed(start: cal.date(byAdding: .hour, value: 1, to: day(1))!, minutes: 10)
        let stats = compute([future])
        #expect(stats.daysTracked == 1)
        #expect(stats.currentStreak == 1)
        #expect(stats.isStreakActiveToday)
    }

    @Test func longestStreakIsUnchangedByGrace() {
        // Catches grace leaking into the longest-streak scan.
        let stats = compute([active(-10), active(-9), active(-8), active(-7), active(-1)])
        #expect(stats.longestStreak == 4)
        #expect(stats.currentStreak == 1)
    }

    @Test func todayMinutesSumsOnlyToday() {
        // Catches goal progress including other days.
        let stats = compute([active(-1), active(0), active(0)])
        #expect(stats.todayMinutes == 20)
    }

    // MARK: Empty

    @Test func emptyUsesTheGivenTodayAndCalendar() {
        // Catches `empty` baking in Calendar.current / .now instead of the injected values.
        let stats = ReadingStats.empty(today: now, calendar: cal)
        #expect(stats.today == cal.startOfDay(for: now))
        #expect(stats.firstDay == stats.today)
        #expect(stats.hasAnyActivity == false)
        #expect(stats.isStreakActiveToday == false)
        #expect(stats.todayMinutes == 0)
        #expect(stats.topBooks.isEmpty)
        #expect(compute([]) == stats)
    }

    // MARK: Top books and ties

    @Test func topBooksSortByMinutesThenTitleThenID() {
        // Catches dictionary-order ties making the "longest book" flip between recomputes.
        let idLow = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let idHigh = UUID(uuidString: "FFFFFFFF-0000-0000-0000-00000000000B")!
        let start = at(2026, 11, 25, 9, 0)
        let rows = [
            timed(start: start, minutes: 30, book: bookB, title: "Zebra"),
            timed(start: start.addingTimeInterval(7200), minutes: 30, book: bookA, title: "Apple"),
            timed(start: start.addingTimeInterval(14400), minutes: 30, book: idHigh, title: "Same"),
            timed(start: start.addingTimeInterval(21600), minutes: 30, book: idLow, title: "Same"),
            timed(start: start.addingTimeInterval(28800), minutes: 50, book: UUID(), title: "Big"),
        ]
        let stats = compute(rows)
        #expect(stats.topBooks.map(\.title) == ["Big", "Apple", "Same", "Same", "Zebra"])
        #expect(stats.topBooks[2].id == idLow)
        #expect(stats.topBooks[3].id == idHigh)
        #expect(stats.longestBookID == stats.topBooks.first?.id)
        #expect(stats.longestBookTitle == "Big")
        #expect(stats.longestBookMinutes == 50)
        #expect(compute(rows.reversed()) == stats)
    }

    @Test func dayTopBookAndBestDayBreakTiesDeterministically() {
        // Catches random top-book and best-day picks when minutes tie.
        let d1 = at(2026, 11, 24, 9, 0)
        let d2 = at(2026, 11, 25, 9, 0)
        let rows = [
            timed(start: d1, minutes: 20, book: bookB, title: "Zebra"),
            timed(start: d1.addingTimeInterval(7200), minutes: 20, book: bookA, title: "Apple"),
            timed(start: d2, minutes: 40, book: bookB, title: "Zebra"),
        ]
        let stats = compute(rows)
        // Day 1: tie on minutes, so the title decides.
        #expect(stats.activityByDay["2026-11-24"]?.topBookTitle == "Apple")
        #expect(stats.activityByDay["2026-11-24"]?.topBookID == bookA)
        // Both days total 40 minutes, so the earlier date is the best day.
        #expect(stats.bestDay?.dayKey == "2026-11-24")
        #expect(stats.bestDay?.topBookTitle == "Apple")
        #expect(compute(rows.reversed()) == stats)
    }

    @Test func dayActivityCarriesTopBookTitle() {
        // Catches ReadingDayActivity.topBookTitle missing, or a phantom entry for an empty day.
        let stats = compute([active(-1)])
        #expect(stats.activityByDay["2026-11-25"]?.topBookTitle == "A")
        #expect(stats.activityByDay["2026-11-20"] == nil)
    }

    @Test func fallBackDayDoesNotSplitASittingIntoTimedAndUntimed() throws {
        // Catches `date + hour * 3600` bucket math on a 25-hour day: after 02:00 -> 01:00 on
        // 2026-11-01 it lands an hour early, so a chunk started at 08:20 looked 80 min off its
        // bucket (outside the 75 min tolerance) and split from its 08:10 neighbour.
        // Also catches `bySettingHour` defaulting to the first 01:00 (EDT) when 01:00 repeats:
        // a 01:30 EST chunk is 90 min after 01:00 EDT and becomes untimed, splitting from 01:10 EST.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        func row(start: Date, hour: Int, minutes: Int) -> ReadingSession {
            let startOfDay = ny.startOfDay(for: start)
            return ReadingSession(
                date: startOfDay,
                dayKey: ReadingSession.makeDayKey(date: startOfDay, calendar: ny),
                hour: hour,
                minutes: minutes,
                bookID: bookA,
                bookTitle: "A",
                bookAuthor: "Author",
                isFreeBook: false,
                createdAt: start.addingTimeInterval(Double(minutes) * 60)
            )
        }
        let eightTen = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 8, minute: 10))!
        let eightTwenty = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 8, minute: 20))!
        let today = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let morningStats = ReadingStats.compute(
            sessions: [
                row(start: eightTen, hour: 8, minutes: 5),
                row(start: eightTwenty, hour: 8, minutes: 5),
            ],
            booksFinished: 0,
            today: today,
            calendar: ny
        )
        #expect(morningStats.totalSessions == 1)

        // Second 01:xx (EST, standard time): 01:10 EST (20 min) + 01:30 EST (5 min).
        let dayStart = ny.startOfDay(for: today)
        let oneEst = ny.date(
            bySettingHour: 1, minute: 0, second: 0, of: dayStart,
            matchingPolicy: .nextTime, repeatedTimePolicy: .last, direction: .forward
        )!
        let oneTenEst = oneEst.addingTimeInterval(10 * 60)
        let oneThirtyEst = oneEst.addingTimeInterval(30 * 60)
        let repeatedHourStats = ReadingStats.compute(
            sessions: [
                row(start: oneTenEst, hour: 1, minutes: 20),
                row(start: oneThirtyEst, hour: 1, minutes: 5),
            ],
            booksFinished: 0,
            today: today,
            calendar: ny
        )
        #expect(repeatedHourStats.totalSessions == 1)
    }
}
