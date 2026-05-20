//
//  ReadingActivitySeeder.swift
//  Pageless
//
//  Debug-only seeder. Generates 113 days of synthetic `ReadingSession` rows so the
//  Reading Activity card and stats screen are demonstrable on a fresh device.
//

#if DEBUG
import Foundation
import SwiftData

enum ReadingActivitySeeder {
    /// Generates ~113 days of synthetic sessions ending today.
    /// Distributes minutes across books using a weighted preference list of the user's library.
    static func seed(audiobooks: [Audiobook], context: ModelContext) {
        // Wipe existing sessions so re-runs are deterministic.
        clear(context: context)

        let daysTracked = 113
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Synthesize a stable list of (id, title, author, isFreeBook).
        // Prefer the user's real books if any; otherwise fall back to recognizable classics
        // so the screens still tell a story on a fresh install.
        let books: [(id: UUID, title: String, author: String, isFreeBook: Bool)] = {
            if !audiobooks.isEmpty {
                return audiobooks.prefix(6).map {
                    (id: $0.id, title: $0.title, author: $0.displayAuthor, isFreeBook: $0.isFreeBook)
                }
            }
            return [
                (UUID(), "Pride and Prejudice", "Jane Austen", true),
                (UUID(), "Moby-Dick", "Herman Melville", true),
                (UUID(), "Frankenstein", "Mary Shelley", true),
                (UUID(), "The Adventures of Sherlock Holmes", "Arthur Conan Doyle", true),
                (UUID(), "The Picture of Dorian Gray", "Oscar Wilde", true),
                (UUID(), "Walden", "Henry David Thoreau", true),
            ]
        }()

        // Weights matching the JS prototype's reading distribution.
        let weights: [Double] = [0.42, 0.20, 0.18, 0.10, 0.06, 0.04]
        let weighted: [(Double, Int)] = {
            var acc: [(Double, Int)] = []
            var running = 0.0
            for (i, _) in books.enumerated() {
                let w = i < weights.count ? weights[i] : (1.0 / Double(books.count))
                running += w
                acc.append((running, i))
            }
            return acc
        }()

        var rng = SeededRNG(seed: 7)

        for offset in stride(from: daysTracked - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
            let isWeekend = (weekday == 1 || weekday == 7)

            var skipChance = isWeekend ? 0.16 : 0.30
            if offset < 14 { skipChance -= 0.08 }  // recency boost
            if rng.next() < skipChance { continue }

            let numSessions: Int = isWeekend
                ? 1 + Int(rng.next() * 3)   // 1...3
                : 1 + Int(rng.next() * 2)   // 1...2

            for _ in 0..<numSessions {
                let r = rng.next()
                let hour: Int = {
                    if r < 0.12 { return 7 + Int(rng.next() * 2) }     // 7–8
                    if r < 0.22 { return 12 + Int(rng.next() * 2) }    // 12–13
                    if r < 0.55 { return 20 + Int(rng.next() * 3) }    // 20–22
                    if r < 0.75 { return 21 + Int(rng.next() * 2) }    // 21–22
                    return Int(rng.next() * 24)
                }()

                let lr = rng.next()
                let minutes: Int = {
                    if lr < 0.12 { return 4 + Int(rng.next() * 8) }      // 4–11
                    if lr < 0.70 { return 14 + Int(rng.next() * 22) }    // 14–35
                    return 36 + Int(rng.next() * 55)                     // 36–90
                }()

                let pick = rng.next()
                let chosenIdx = weighted.first(where: { pick <= $0.0 })?.1 ?? 0
                let book = books[chosenIdx]

                let startOfDay = calendar.startOfDay(for: day)
                let session = ReadingSession(
                    date: startOfDay,
                    dayKey: ReadingSession.makeDayKey(date: startOfDay, calendar: calendar),
                    hour: hour,
                    minutes: minutes,
                    bookID: book.id,
                    bookTitle: book.title,
                    bookAuthor: book.author,
                    isFreeBook: book.isFreeBook
                )
                context.insert(session)
            }
        }

        try? context.save()
    }

    static func clear(context: ModelContext) {
        let descriptor = FetchDescriptor<ReadingSession>()
        let existing = (try? context.fetch(descriptor)) ?? []
        for s in existing { context.delete(s) }
        try? context.save()
    }
}

/// mulberry32-equivalent. Deterministic so seeded data is reproducible.
private struct SeededRNG {
    private var state: UInt32
    init(seed: UInt32) { state = seed }
    mutating func next() -> Double {
        state &+= 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / Double(UInt32.max)
    }
}
#endif
