//
//  MomentAnalyzing.swift
//  Ebooker
//

import Foundation

protocol MomentAnalyzing: Sendable {
    func analyzeMoment(transcript: String, audiobookTitle: String?) async throws -> MomentNamingService.MomentAnalysis
}
