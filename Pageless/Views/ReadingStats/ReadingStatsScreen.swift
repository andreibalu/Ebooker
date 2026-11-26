//
//  ReadingStatsScreen.swift
//  Pageless
//

import SwiftData
import SwiftUI
import UIKit

/// Live-data wrapper around `ReadingStatsView`. Owns the SwiftData queries, the midnight-refreshed
/// `today` reference date, `@AppStorage` palette & daily goal preferences, and targeted cover fetches
/// for only the displayed books (≤6 IDs). Used by both Favorites and Settings → Reading Activity.
struct ReadingStatsScreen: View {
    var backLabel: String = "Library"

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReadingSession.date, order: .reverse) private var readingSessions: [ReadingSession]
    @Query private var audiobooks: [Audiobook]

    @AppStorage(HeatmapPalette.storageKey) private var paletteRaw: String = HeatmapPalette.amber.rawValue
    @AppStorage(DailyListeningGoal.storageKey) private var dailyGoalMinutes: Int = 0

    @State private var today: Date = .now
    @State private var bookCovers: [UUID: UIImage] = [:]

    private var stats: ReadingStats {
        ReadingStats.compute(
            sessions: readingSessions,
            booksFinished: audiobooks.filter(\.isFinished).count,
            today: today
        )
    }

    private var paletteBinding: Binding<HeatmapPalette> {
        Binding(
            get: { HeatmapPalette.fromStorage(paletteRaw) },
            set: { paletteRaw = $0.rawValue }
        )
    }

    /// Only the ≤6 book IDs rendered on screen (best day + top 5 books, which includes longestBook).
    private var displayedBookIDs: [UUID] {
        var ids: [UUID] = []
        if let bestID = stats.bestDay?.topBookID {
            ids.append(bestID)
        }
        for book in stats.topBooks.prefix(5) where !ids.contains(book.id) {
            ids.append(book.id)
        }
        return ids
    }

    var body: some View {
        ReadingStatsView(
            stats: stats,
            palette: paletteBinding,
            dailyGoalMinutes: $dailyGoalMinutes,
            bookCovers: bookCovers,
            backLabel: backLabel
        )
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            today = .now
        }
        .task(id: displayedBookIDs) {
            loadDisplayedCovers(for: displayedBookIDs)
        }
    }

    private func loadDisplayedCovers(for ids: [UUID]) {
        guard !ids.isEmpty else {
            bookCovers = [:]
            return
        }
        let descriptor = FetchDescriptor<Audiobook>(
            predicate: #Predicate<Audiobook> { book in
                ids.contains(book.id)
            }
        )
        guard let fetched = try? modelContext.fetch(descriptor) else { return }
        var decoded: [UUID: UIImage] = [:]
        for book in fetched {
            if let data = book.coverArtData, let image = UIImage(data: data) {
                decoded[book.id] = image
            }
        }
        bookCovers = decoded
    }
}
