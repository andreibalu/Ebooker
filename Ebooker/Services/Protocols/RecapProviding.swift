//
//  RecapProviding.swift
//  Ebooker
//

import Foundation

protocol RecapProviding: Sendable {
    func generateRecap(transcript: String, audiobookTitle: String?) async throws -> String
}
