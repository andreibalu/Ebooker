//
//  LyricsProviding.swift
//  Ebooker
//

import Foundation

@MainActor
protocol LyricsProviding: AnyObject {
    var modelState: WhisperModelState { get }
    func downloadModel() async
    func deleteModel()
    func transcribeTrack(
        _ track: AudioTrack,
        in audiobook: Audiobook,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> TrackLyrics
    func loadCachedLyrics(for track: AudioTrack, in audiobook: Audiobook) -> TrackLyrics?
    func deleteCachedLyrics(for track: AudioTrack, in audiobook: Audiobook)
}
