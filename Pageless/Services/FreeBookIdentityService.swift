//
//  FreeBookIdentityService.swift
//  Pageless
//

import Foundation
import SwiftData

/// Centralizes free-book identity lookup without using computed SwiftData accessors in a predicate.
enum FreeBookIdentityService {
    enum Classification: Int, Equatable, Sendable {
        case downloadedActive
        case streamingActive
        case archived
    }

    struct Match {
        let audiobook: Audiobook
        let classification: Classification
    }

    /// Returns the persisted identity for a catalog book. When historical duplicates exist,
    /// playable downloaded rows win over active streaming rows, which win over archived rows.
    /// Ties prefer the oldest row and then UUID order so fetch ordering never affects the result.
    static func match(catalogId: String, modelContext: ModelContext) throws -> Match? {
        let books = try modelContext.fetch(FetchDescriptor<Audiobook>())
        return books
            .filter { $0.isFreeBook && $0.catalogId == catalogId }
            .map { audiobook in
                let classification: Classification
                if audiobook.isArchived {
                    classification = .archived
                } else if audiobook.isDownloaded {
                    classification = .downloadedActive
                } else {
                    classification = .streamingActive
                }
                return Match(audiobook: audiobook, classification: classification)
            }
            .sorted { lhs, rhs in
                if lhs.classification.rawValue != rhs.classification.rawValue {
                    return lhs.classification.rawValue < rhs.classification.rawValue
                }
                if lhs.audiobook.createdAt != rhs.audiobook.createdAt {
                    return lhs.audiobook.createdAt < rhs.audiobook.createdAt
                }
                return lhs.audiobook.id.uuidString < rhs.audiobook.id.uuidString
            }
            .first
    }

    /// Reuses a persisted free-book row while replacing only its local-file representation.
    /// Book-level identity, progress, moments, favorites, and equalizer state remain untouched.
    static func promoteToDownloaded(
        _ audiobook: Audiobook,
        folderName: String,
        title: String,
        author: String,
        coverArtData: Data?,
        tracks incomingTracks: [AudioTrack],
        modelContext: ModelContext,
        saveModelContext: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Audiobook {
        let originalTitle = audiobook.title
        let originalAuthor = audiobook.author
        let originalFolderName = audiobook.folderName
        let originalCoverArtData = audiobook.coverArtData
        let originalTracks = audiobook.tracks
        let originalTotalDuration = audiobook.totalDuration
        let originalIsDownloaded = audiobook.isDownloaded
        let originalIsArchived = audiobook.isArchived
        let originalTrackValues = originalTracks.map {
            ($0, $0.title, $0.originalFileName, $0.storedFileName, $0.duration, $0.remoteURLString)
        }
        var existingByOrder = Dictionary(
            uniqueKeysWithValues: audiobook.tracks.map { ($0.orderIndex, $0) }
        )
        var promotedTracks: [AudioTrack] = []
        var insertedTracks: [AudioTrack] = []

        for incoming in incomingTracks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let track: AudioTrack
            if let existing = existingByOrder.removeValue(forKey: incoming.orderIndex) {
                existing.title = incoming.title
                existing.originalFileName = incoming.originalFileName
                existing.storedFileName = incoming.storedFileName
                existing.duration = incoming.duration
                existing.remoteURLString = incoming.remoteURLString
                track = existing
            } else {
                incoming.audiobook = audiobook
                modelContext.insert(incoming)
                insertedTracks.append(incoming)
                track = incoming
            }
            promotedTracks.append(track)
        }

        for obsolete in existingByOrder.values {
            modelContext.delete(obsolete)
        }

        audiobook.title = title
        audiobook.author = author
        audiobook.folderName = folderName
        audiobook.coverArtData = coverArtData ?? audiobook.coverArtData
        audiobook.tracks = promotedTracks
        audiobook.totalDuration = promotedTracks.reduce(0) { $0 + $1.duration }
        audiobook.isDownloaded = true
        audiobook.isArchived = false
        do {
            try saveModelContext(modelContext)
            return audiobook
        } catch {
            for track in insertedTracks {
                modelContext.delete(track)
                track.audiobook = nil
            }
            for track in existingByOrder.values {
                modelContext.insert(track)
            }
            for (track, title, originalFileName, storedFileName, duration, remoteURLString) in originalTrackValues {
                track.title = title
                track.originalFileName = originalFileName
                track.storedFileName = storedFileName
                track.duration = duration
                track.remoteURLString = remoteURLString
                track.audiobook = audiobook
            }
            audiobook.title = originalTitle
            audiobook.author = originalAuthor
            audiobook.folderName = originalFolderName
            audiobook.coverArtData = originalCoverArtData
            audiobook.tracks = originalTracks
            audiobook.totalDuration = originalTotalDuration
            audiobook.isDownloaded = originalIsDownloaded
            audiobook.isArchived = originalIsArchived
            throw error
        }
    }

}
