//
//  ReadingSessionRecorder.swift
//  Pageless
//

import Foundation
import SwiftData

/// Accumulates wall-clock playback seconds and emits `ReadingSession` rows.
///
/// Called from `AudioPlayerManager`'s periodic time observer (with `isPlaying`) and on lifecycle
/// boundaries (pause, track change, audiobook change, app background, finish). The observer fires
/// per second of *media* time, so at 2x speed it ticks every half second. The recorder therefore
/// credits the real time elapsed between ticks, not a fixed second per tick.
/// Chunks are flushed every ~5 minutes of continuous play so an evening session is bucketed
/// into a couple of hour rows rather than smeared across one wall-clock hour. Each row's
/// `createdAt` is when its chunk ended; `ReadingStats` uses it to coalesce chunks back into one
/// logical session.
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
    /// Monotonic time of the previous tick of the current chunk, or nil right after start or a flush.
    private var lastTickUptime: TimeInterval?

    /// Flush after this many seconds of continuous play (5 minutes). Keeps hour bucketing fine-grained.
    private let flushThresholdSeconds: Double = 5 * 60
    /// A single tick never credits more than this, so a stall, buffering gap or suspended app cannot
    /// add a lump of time that was not spent listening.
    private let maxSecondsPerTick: Double = 3
    /// Credited for the first tick after a start or flush, when there is no previous tick to measure from.
    private let firstTickSeconds: Double = 1
    /// Below this, a chunk is discarded (avoids noise from brief scrubbing or accidental taps).
    private let minSecondsToRecord: Double = 30

    /// Called from the periodic time observer while playback is active. Credits the real time since
    /// the previous tick (capped at `maxSecondsPerTick`), or `firstTickSeconds` for the first tick of
    /// a chunk. `uptime` is a monotonic clock, so wall-clock changes cannot skew it.
    func tick(
        audiobook: Audiobook,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        context: ModelContext?
    ) {
        // Switching books mid-stream: close out the old session, start a new one.
        // `end`, not `flush`: flush keeps `active`, so the new book's chunk would be filed under the
        // old book and dropped as noise on every following tick.
        if let active, active.id != audiobook.id {
            end(context: context)
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

        let credited: Double
        if let last = lastTickUptime {
            credited = min(max(uptime - last, 0), maxSecondsPerTick)
        } else {
            credited = firstTickSeconds
        }
        lastTickUptime = uptime
        accumulatedSeconds += credited

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
            lastTickUptime = nil
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
            isFreeBook: active.isFreeBook,
            createdAt: Date()
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
