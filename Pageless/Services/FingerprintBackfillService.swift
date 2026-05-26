//
//  FingerprintBackfillService.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData

/// One-shot background pass that fills in `AudioTrack.contentFingerprint` for tracks imported
/// before fingerprinting existed. Lets pre-sync libraries be recoverable on a new device by
/// re-importing the same files.
///
/// Runs from `AppDelegate` after the container is ready. Iterates downloaded tracks lazily,
/// computes a fingerprint per file, persists in small batches, and stops if interrupted.
enum FingerprintBackfillService {
    private static let log = Logger(subsystem: "andreibaludev.Pageless", category: "Fingerprint")

    static func runIfNeeded(modelContainer: ModelContainer) {
        Task.detached(priority: .utility) {
            await run(modelContainer: modelContainer)
        }
    }

    private static func run(modelContainer: ModelContainer) async {
        let context = ModelContext(modelContainer)
        // Filter in-memory: `#Predicate` can't see the private backing field, and the cohort is small.
        guard let allTracks = try? context.fetch(FetchDescriptor<AudioTrack>()) else { return }
        let tracks = allTracks.filter { $0.contentFingerprint == nil }
        guard !tracks.isEmpty else { return }
        log.info("Backfilling fingerprints for \(tracks.count, privacy: .public) track(s)")

        var processed = 0
        for track in tracks {
            // Skip streaming-only tracks — they have no local file.
            if track.remoteURL != nil, (track.storedFileName.isEmpty) { continue }
            guard let book = track.audiobook else { continue }
            guard let fileURL = try? LibraryImportService.fileURL(for: track, in: book),
                  FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                continue
            }
            if let hex = await LibraryImportService.fingerprint(url: fileURL, durationSeconds: track.duration) {
                track.contentFingerprint = hex
                processed += 1
                if processed % 5 == 0 {
                    try? context.save()
                }
            }
        }
        try? context.save()
        log.info("Fingerprint backfill done — wrote \(processed, privacy: .public) digest(s)")
    }
}
