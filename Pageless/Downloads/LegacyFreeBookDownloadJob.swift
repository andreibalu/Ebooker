//
//  LegacyFreeBookDownloadJob.swift
//  Pageless
//

import Foundation

struct LegacyFreeBookDownloadJob: Codable, Equatable {
    enum Phase: String, Codable {
        case downloading
        case failed
    }

    let attemptID: UUID
    let catalogEntry: FreeBookCatalogEntry
    let folderName: String
    var completedIndexes: Set<Int>
    var phase: Phase
    var lastError: String?

    var catalogID: String { catalogEntry.id }
}
struct LegacyFreeBookDownloadTaskIdentity: Hashable, Sendable {
    let catalogID: String
    let attemptID: UUID
    let trackIndex: Int

    init(catalogID: String, attemptID: UUID, trackIndex: Int) {
        self.catalogID = catalogID
        self.attemptID = attemptID
        self.trackIndex = trackIndex
    }

    var description: String {
        let payload = LegacyTaskPayload(
            catalogID: catalogID,
            attemptID: attemptID.uuidString,
            trackIndex: trackIndex
        )
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        return "legacy-freebook:" + data.base64EncodedString()
    }

    init?(description: String) {
        guard description.hasPrefix("legacy-freebook:"),
              let data = Data(
                base64Encoded: String(description.dropFirst("legacy-freebook:".count))
              ),
              let payload = try? JSONDecoder().decode(LegacyTaskPayload.self, from: data),
              let attemptID = UUID(uuidString: payload.attemptID),
              payload.trackIndex >= 0
        else { return nil }
        catalogID = payload.catalogID
        self.attemptID = attemptID
        trackIndex = payload.trackIndex
    }

    private struct LegacyTaskPayload: Codable {
        let catalogID: String
        let attemptID: String
        let trackIndex: Int
    }
}
