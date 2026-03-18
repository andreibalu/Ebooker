//
//  AudioExtractionService.swift
//  Ebooker
//

import AVFoundation
import Foundation

/// Extracts audio segments from a track for transcription.
struct AudioExtractionService: AudioExtracting {
    private let segmentDuration: Double = 50

    /// Extracts an audio segment between two absolute time points.
    /// - Parameters:
    ///   - fileURL: URL of the audio file
    ///   - startSeconds: Start time in seconds
    ///   - endSeconds: End time in seconds
    /// - Returns: URL of a temporary audio file
    func extractSegment(
        from fileURL: URL,
        startSeconds: Double,
        endSeconds: Double
    ) async throws -> URL {
        let segmentLength = endSeconds - startSeconds

        guard segmentLength > 0 else {
            throw AudioExtractionError.invalidRange
        }

        let asset = AVURLAsset(url: fileURL)
        let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        )

        guard let exportSession else {
            throw AudioExtractionError.exportSessionCreationFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: segmentLength, preferredTimescale: 600)
        )

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw error
            }
            throw AudioExtractionError.exportFailed
        }

        return outputURL
    }

    /// Extracts a segment centered on the given time (convenience wrapper).
    /// - Parameters:
    ///   - fileURL: URL of the audio file
    ///   - currentTime: Center point in seconds
    ///   - duration: Total track duration in seconds
    /// - Returns: URL of a temporary audio file
    func extractSegment(
        from fileURL: URL,
        currentTime: Double,
        duration: Double
    ) async throws -> URL {
        let startTime = max(0, currentTime - segmentDuration)
        let endTime = min(duration, currentTime + segmentDuration)
        return try await extractSegment(from: fileURL, startSeconds: startTime, endSeconds: endTime)
    }
}

enum AudioExtractionError: LocalizedError {
    case invalidRange
    case exportSessionCreationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            "Could not extract audio segment."
        case .exportSessionCreationFailed:
            "Could not prepare audio for transcription."
        case .exportFailed:
            "Could not extract audio segment."
        }
    }
}
