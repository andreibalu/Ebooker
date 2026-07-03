//
//  DownloadActivityAggregation.swift
//  Pageless
//

import Foundation

extension DownloadActivitySnapshot {
    @MainActor
    static func aggregate(
        entries: [LibriVoxDownloadManager.Entry]
    ) -> DownloadActivitySnapshot? {
        guard !entries.isEmpty else { return nil }

        let runnable = entries.filter { entry in
            switch entry.phase {
            case .preparing, .downloading, .cancelling: true
            case .failed, .complete: false
            }
        }
        if !runnable.isEmpty { return aggregateRunnable(runnable) }

        let failed = entries.filter { $0.phase == .failed }
        if !failed.isEmpty {
            return .init(
                title: "Download paused",
                activeBookCount: failed.count,
                completedTracks: failed.reduce(0) { $0 + max(0, $1.completedTracks) },
                totalTracks: failed.reduce(0) { $0 + max(0, $1.totalTracks) },
                progress: weightedProgress(for: failed),
                phase: .failed,
                failureMessage: failed.compactMap(\.errorMessage).first
            )
        }

        return .init(
            title: "Downloaded",
            activeBookCount: entries.count,
            completedTracks: entries.reduce(0) { $0 + max(0, $1.completedTracks) },
            totalTracks: entries.reduce(0) { $0 + max(0, $1.totalTracks) },
            progress: 1,
            phase: .complete,
            failureMessage: nil
        )
    }

    @MainActor
    private static func aggregateRunnable(
        _ entries: [LibriVoxDownloadManager.Entry]
    ) -> DownloadActivitySnapshot {
        .init(
            title: entries.count == 1
                ? entries[0].metadata.title
                : "\(entries.count) books downloading",
            activeBookCount: entries.count,
            completedTracks: entries.reduce(0) { $0 + max(0, $1.completedTracks) },
            totalTracks: entries.reduce(0) { $0 + max(0, $1.totalTracks) },
            progress: weightedProgress(for: entries),
            phase: entries.contains { $0.phase == .downloading } ? .downloading : .preparing,
            failureMessage: nil
        )
    }

    @MainActor
    private static func weightedProgress(
        for entries: [LibriVoxDownloadManager.Entry]
    ) -> Double {
        let total = entries.reduce(0) { $0 + max(0, $1.totalTracks) }
        guard total > 0 else { return 0 }
        let completed = entries.reduce(0.0) { partial, entry in
            let fraction = entry.phase == .cancelling
                ? 0
                : min(1, max(0, entry.currentTrackFraction))
            return partial + Double(max(0, entry.completedTracks)) + fraction
        }
        return min(1, max(0, completed / Double(total)))
    }
}
