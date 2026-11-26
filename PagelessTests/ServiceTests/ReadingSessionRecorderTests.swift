//
//  ReadingSessionRecorderTests.swift
//  PagelessTests
//

import Foundation
import SwiftData
import Testing
@testable import Pageless

/// Isolated on purpose: E2E never plays two books for more than 30 s each, so a recorder that
/// silently drops the second book's time would pass every E2E run (slice 01 review round 1).
@MainActor
struct ReadingSessionRecorderTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Audiobook.self, AudioTrack.self, Moment.self, ReadingSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func rows(in context: ModelContext) throws -> [ReadingSession] {
        try context.fetch(FetchDescriptor<ReadingSession>())
    }

    /// Ticks once per second from `start` for `seconds` ticks; returns the next uptime.
    @discardableResult
    private func play(
        _ recorder: ReadingSessionRecorder,
        _ book: Audiobook,
        from start: TimeInterval,
        seconds: Int,
        context: ModelContext
    ) -> TimeInterval {
        for i in 0..<seconds {
            recorder.tick(audiobook: book, uptime: start + TimeInterval(i), context: context)
        }
        return start + TimeInterval(seconds)
    }

    @Test func switchingBooksRecordsBothBooks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let recorder = ReadingSessionRecorder()
        let bookA = Audiobook(title: "A", folderName: "a", totalDuration: 600)
        let bookB = Audiobook(title: "B", folderName: "b", totalDuration: 600)

        let next = play(recorder, bookA, from: 1000, seconds: 60, context: context)
        play(recorder, bookB, from: next, seconds: 60, context: context)
        recorder.flush(context: context)

        let saved = try rows(in: context)
        #expect(saved.count == 2)
        let minutesByBook = Dictionary(uniqueKeysWithValues: saved.map { ($0.bookID, $0.minutes) })
        #expect(minutesByBook[bookA.id] == 1)
        #expect(minutesByBook[bookB.id] == 1)
    }

    @Test func stallBetweenTicksCreditsAtMostTheCap() throws {
        // E2E can't produce a long stall while playing; dropping the per-tick cap would credit buffering and background-wake gaps as listening.
        let container = try makeContainer()
        let context = container.mainContext
        let recorder = ReadingSessionRecorder()
        let book = Audiobook(title: "A", folderName: "a", totalDuration: 600)

        // 60 s of normal ticks, then 20 ticks that each follow a 60 s stall. Each stall may credit
        // only the 3 s cap: 60 + 20 * 3 = 120 s = 2 min, not ~21 min.
        var uptime = play(recorder, book, from: 1000, seconds: 60, context: context)
        for _ in 0..<20 {
            uptime += 60
            recorder.tick(audiobook: book, uptime: uptime, context: context)
        }
        recorder.flush(context: context)

        let total = try rows(in: context).reduce(0) { $0 + $1.minutes }
        #expect(total == 2)
    }
}
