//
//  ReadingSessionRecorder.swift
//  Pageless
//

import Foundation
import SwiftData

/// Accumulates wall-clock playback seconds and emits `ReadingSession` rows.
///
/// Called from `AudioPlayerManager`'s periodic 1-second time observer (with `isPlaying`)
/// and on lifecycle boundaries (pause, track change, audiobook change, app background, finish).
/// Chunks are flushed every ~5 minutes of continuous play so an evening session is bucketed
/// into a couple of hour rows rather than smeared across one wall-clock hour.
@MainActor
final class ReadingSessionRecorder {
    private struct ActiveBook {
        let id: UUID
        let title: String
        let author: String
        let isFreeBook: Bool
    }

    private var active: ActiveBook?
    private var accumulatedSeconds: Double = 0
    private var chunkStartDate: Date?
    private var chunkStartHour: Int?

    /// Flush after this many seconds of continuous play (5 minutes). Keeps hour bucketing fine-grained.
    private let flushThresholdSeconds: Double = 5 * 60
    /// Below this, a chunk is discarded (avoids noise from brief scrubbing or accidental taps).
    private let minSecondsToRecord: Double = 30

    /// Called once per second from the periodic time observer while playback is active.
    /// `secondsElapsed` defaults to 1.0; pass a different value if you ever drive this from
    /// a non-1s cadence.
    func tick(
        audiobook: Audiobook,
        secondsElapsed: Double = 1.0,
        context: ModelContext?
    ) {
        // Switching books mid-stream: close out the old session, start a new one.
        if let active, active.id != audiobook.id {
            flush(context: context)
        }
        if active == nil {
            active = ActiveBook(
                id: audiobook.id,
                title: audiobook.title,
                author: audiobook.displayAuthor,
                isFreeBook: audiobook.isFreeBook
            )
        }

        if chunkStartDate == nil {
            let now = Date()
            chunkStartDate = now
            chunkStartHour = Calendar.current.component(.hour, from: now)
        }

        accumulatedSeconds += secondsElapsed

        if accumulatedSeconds >= flushThresholdSeconds {
            flush(context: context)
        }
    }

    /// Persist whatever has accumulated. Resets chunk timing but keeps `active` so a
    /// following tick continues the same logical book.
    func flush(context: ModelContext?) {
        defer {
            accumulatedSeconds = 0
            chunkStartDate = nil
            chunkStartHour = nil
        }

        guard let active else { return }
        guard accumulatedSeconds >= minSecondsToRecord else { return }

        let when = chunkStartDate ?? Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: when)
        let hour = chunkStartHour ?? calendar.component(.hour, from: when)
        let minutes = max(1, Int((accumulatedSeconds / 60).rounded()))

        let session = ReadingSession(
            date: startOfDay,
            dayKey: ReadingSession.makeDayKey(date: startOfDay, calendar: calendar),
            hour: hour,
            minutes: minutes,
            bookID: active.id,
            bookTitle: active.title,
            bookAuthor: active.author,
            isFreeBook: active.isFreeBook
        )

        context?.insert(session)
        try? context?.save()
    }

    /// Flush and forget the active book — call when playback truly ends (book finished, player torn down).
    func end(context: ModelContext?) {
        flush(context: context)
        active = nil
    }
}
