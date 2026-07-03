//
//  LibriVoxDownloadJob.swift
//  Pageless
//

import Foundation

struct LibriVoxDownloadJob: Codable, Equatable, Sendable {
    enum Target: Codable, Equatable, Sendable {
        case fresh
        case existing(audiobookID: UUID)
    }

    enum Phase: String, Codable, Equatable, Sendable {
        case preparing
        case downloading
        case failed
    }

    let catalogID: String
    let attemptID: UUID
    let title: String
    let target: Target
    let stagingFolderName: String
    var tracks: [LibriVoxDownloadTrack]
    var completedIndexes: Set<Int>
    var phase: Phase
    var lastError: String?
}

struct LibriVoxDownloadTrack: Codable, Equatable, Sendable {
    let title: String
    let remoteURL: URL
    let durationSeconds: TimeInterval
    let storedFileName: String
}

struct LibriVoxDownloadTaskIdentity: Hashable, Sendable {
    let catalogID: String
    let attemptID: UUID
    let trackIndex: Int

    var description: String {
        "\(catalogID)|\(attemptID.uuidString)|\(trackIndex)"
    }

    init(catalogID: String, attemptID: UUID, trackIndex: Int) {
        self.catalogID = catalogID
        self.attemptID = attemptID
        self.trackIndex = trackIndex
    }

    init?(description: String) {
        let components = description.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3,
              !components[0].isEmpty,
              let attemptID = UUID(uuidString: String(components[1])),
              let trackIndex = Int(components[2]),
              trackIndex >= 0
        else { return nil }

        self.init(
            catalogID: String(components[0]),
            attemptID: attemptID,
            trackIndex: trackIndex
        )
    }
}
