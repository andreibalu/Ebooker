//
//  CachedLibriVoxTrack.swift
//  Pageless
//

import Foundation

struct CachedLibriVoxTrack: Codable {
    let title: String
    let listenURL: String
    let durationSeconds: Double
    let orderIndex: Int
}
