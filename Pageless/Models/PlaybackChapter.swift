//
//  PlaybackChapter.swift
//  Pageless
//

import Foundation

/// A chapter marker inside one audio file (an m4b/m4a/mp3 chapter atom), in seconds from the
/// start of that file. Read from the asset at load time; never persisted.
nonisolated struct ChapterMarker: Equatable, Sendable {
    let title: String
    let start: Double
    let end: Double
}

/// One navigable chapter of the book that is playing. A chapter is either a whole track (one file
/// per chapter, e.g. LibriVox sections) or a time range inside a track (embedded chapters in a
/// single-file m4b, or Audiobookshelf server chapters).
nonisolated struct PlaybackChapter: Equatable, Identifiable, Sendable {
    /// Position in the book's chapter list.
    let index: Int
    let title: String
    /// Positional index into `Audiobook.sortedTracks`.
    let trackIndex: Int
    /// Seconds from the start of the track.
    let start: Double
    let duration: Double

    var id: Int { index }
}

/// Pure chapter-list construction and lookup, shared by the player, its chapter sheet and CarPlay.
nonisolated enum PlaybackChapterList {
    /// A chapter that starts this close to the requested time counts as "already reached", so a
    /// seek that lands a hair early still highlights the chapter that was tapped.
    static let startTolerance: Double = 0.25

    /// Builds the chapter list for a book from its tracks plus any embedded markers per track.
    /// A track with two or more usable markers contributes one chapter per marker; every other
    /// track contributes itself as a single chapter.
    static func build(
        trackTitles: [String],
        trackDurations: [Double],
        markersByTrack: [Int: [ChapterMarker]]
    ) -> [PlaybackChapter] {
        var chapters: [PlaybackChapter] = []
        for (trackIndex, trackTitle) in trackTitles.enumerated() {
            let trackDuration = trackDurations.indices.contains(trackIndex) ? safe(trackDurations[trackIndex]) : 0
            let markers = sanitized(markersByTrack[trackIndex] ?? [], trackDuration: trackDuration)
            if markers.count >= 2 {
                for marker in markers {
                    chapters.append(PlaybackChapter(
                        index: chapters.count,
                        title: marker.title.isEmpty ? "Chapter \(chapters.count + 1)" : marker.title,
                        trackIndex: trackIndex,
                        start: marker.start,
                        duration: max(marker.end - marker.start, 0)
                    ))
                }
            } else {
                chapters.append(PlaybackChapter(
                    index: chapters.count,
                    title: trackTitle,
                    trackIndex: trackIndex,
                    start: 0,
                    duration: trackDuration
                ))
            }
        }
        return chapters
    }

    /// Orders markers, drops unusable ones (non-finite, past the end of the file, duplicate starts)
    /// and recomputes each end from the next start so the ranges tile the file without gaps.
    static func sanitized(_ markers: [ChapterMarker], trackDuration: Double) -> [ChapterMarker] {
        let duration = safe(trackDuration)
        var ordered = markers
            .filter { $0.start.isFinite && $0.start >= 0 }
            .filter { duration <= 0 || $0.start < duration - 0.5 }
            .sorted { $0.start < $1.start }
        var deduped: [ChapterMarker] = []
        for marker in ordered {
            if let last = deduped.last, marker.start - last.start < 0.5 { continue }
            deduped.append(marker)
        }
        ordered = deduped
        guard !ordered.isEmpty else { return [] }

        return ordered.enumerated().map { offset, marker in
            // The first chapter owns the head of the file, so nothing before it is unreachable.
            let start = offset == 0 ? 0 : marker.start
            let end: Double
            if offset + 1 < ordered.count {
                end = ordered[offset + 1].start
            } else if duration > 0 {
                end = duration
            } else {
                end = marker.end.isFinite ? max(marker.end, start) : start
            }
            return ChapterMarker(
                title: marker.title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                end: end
            )
        }
    }

    /// The chapter that contains `time` in track `trackIndex`: the last chapter that starts at or
    /// before that position. A position before the first chapter maps to the first chapter.
    static func chapterIndex(in chapters: [PlaybackChapter], trackIndex: Int, time: Double) -> Int? {
        guard !chapters.isEmpty else { return nil }
        let position = time.isFinite ? time : 0
        var found: Int?
        for chapter in chapters {
            if chapter.trackIndex < trackIndex
                || (chapter.trackIndex == trackIndex && chapter.start <= position + startTolerance) {
                found = chapter.index
            } else {
                break
            }
        }
        return found ?? 0
    }

    private static func safe(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }
}
