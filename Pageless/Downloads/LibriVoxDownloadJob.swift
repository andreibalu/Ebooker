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
        case finalizing
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
    var destinationFolderName: String? = nil
    var backupFolderName: String? = nil
    var fileMetadata: [Int: LibriVoxDownloadFileMetadata] = [:]

    private enum CodingKeys: String, CodingKey {
        case catalogID, attemptID, title, target, stagingFolderName, tracks
        case completedIndexes, phase, lastError, destinationFolderName
        case backupFolderName, fileMetadata
    }

    init(
        catalogID: String,
        attemptID: UUID,
        title: String,
        target: Target,
        stagingFolderName: String,
        tracks: [LibriVoxDownloadTrack],
        completedIndexes: Set<Int>,
        phase: Phase,
        lastError: String?,
        destinationFolderName: String? = nil,
        backupFolderName: String? = nil,
        fileMetadata: [Int: LibriVoxDownloadFileMetadata] = [:]
    ) {
        self.catalogID = catalogID
        self.attemptID = attemptID
        self.title = title
        self.target = target
        self.stagingFolderName = stagingFolderName
        self.tracks = tracks
        self.completedIndexes = completedIndexes
        self.phase = phase
        self.lastError = lastError
        self.destinationFolderName = destinationFolderName
        self.backupFolderName = backupFolderName
        self.fileMetadata = fileMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogID = try container.decode(String.self, forKey: .catalogID)
        attemptID = try container.decode(UUID.self, forKey: .attemptID)
        title = try container.decode(String.self, forKey: .title)
        target = try container.decode(Target.self, forKey: .target)
        stagingFolderName = try container.decode(String.self, forKey: .stagingFolderName)
        let decodedTracks = try container.decode([LibriVoxDownloadTrack].self, forKey: .tracks)
        tracks = decodedTracks.enumerated().map { index, track in
            track.orderIndexWasMissing ? track.withOrderIndex(index) : track
        }
        completedIndexes = try container.decode(Set<Int>.self, forKey: .completedIndexes)
        phase = try container.decode(Phase.self, forKey: .phase)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        destinationFolderName = try container.decodeIfPresent(String.self, forKey: .destinationFolderName)
        backupFolderName = try container.decodeIfPresent(String.self, forKey: .backupFolderName)
        fileMetadata = try container.decodeIfPresent(
            [Int: LibriVoxDownloadFileMetadata].self,
            forKey: .fileMetadata
        ) ?? [:]
    }
}

struct LibriVoxDownloadTrack: Codable, Equatable, Sendable {
    let title: String
    let remoteURL: URL
    let durationSeconds: TimeInterval
    let storedFileName: String
    let orderIndex: Int
    let orderIndexWasMissing: Bool

    private enum CodingKeys: String, CodingKey {
        case title, remoteURL, durationSeconds, storedFileName, orderIndex
    }

    init(
        title: String,
        remoteURL: URL,
        durationSeconds: TimeInterval,
        storedFileName: String,
        orderIndex: Int
    ) {
        self.title = title
        self.remoteURL = remoteURL
        self.durationSeconds = durationSeconds
        self.storedFileName = storedFileName
        self.orderIndex = orderIndex
        self.orderIndexWasMissing = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        remoteURL = try container.decode(URL.self, forKey: .remoteURL)
        durationSeconds = try container.decode(TimeInterval.self, forKey: .durationSeconds)
        storedFileName = try container.decode(String.self, forKey: .storedFileName)
        let decodedOrderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex)
        orderIndex = decodedOrderIndex ?? -1
        orderIndexWasMissing = decodedOrderIndex == nil
    }

    func withOrderIndex(_ orderIndex: Int) -> Self {
        .init(
            title: title,
            remoteURL: remoteURL,
            durationSeconds: durationSeconds,
            storedFileName: storedFileName,
            orderIndex: orderIndex
        )
    }
}

struct LibriVoxDownloadFileMetadata: Codable, Equatable, Sendable {
    let byteCount: Int64
    let sha256: String
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
