//
//  FreeBookCatalogEntry.swift
//  Pageless
//

import Foundation

struct FreeBookCatalogEntry: Codable, Identifiable, Hashable {
    static func == (lhs: FreeBookCatalogEntry, rhs: FreeBookCatalogEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let title: String
    let author: String
    let description: String
    let coverAssetName: String?
    let totalDurationSeconds: Double
    let downloadSizeMB: Double
    let tracks: [FreeBookTrackEntry]
}

struct FreeBookTrackEntry: Codable, Identifiable {
    let id: String
    let title: String
    let fileName: String
    let downloadURL: String
    let durationSeconds: Double
    let orderIndex: Int
}
