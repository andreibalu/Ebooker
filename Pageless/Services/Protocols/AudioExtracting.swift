//
//  AudioExtracting.swift
//  Pageless
//

import Foundation

protocol AudioExtracting: Sendable {
    func extractSegment(from fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> URL
    func extractSegment(from fileURL: URL, currentTime: Double, duration: Double) async throws -> URL
}
