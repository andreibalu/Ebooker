//
//  WhisperKitService.swift
//  Ebooker
//

import Foundation
import WhisperKit

@MainActor
final class WhisperKitService: ObservableObject, LyricsProviding {

    // MARK: - Constants

    static let modelName = "openai_whisper-base.en"

    // MARK: - Published state

    @Published private(set) var modelState: WhisperModelState = .notDownloaded

    // MARK: - Private

    private var whisperKit: WhisperKit?
    private var downloadTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        checkExistingModel()
    }

    // MARK: - Model management

    private func checkExistingModel() {
        Task {
            let exists = await WhisperKit.modelExists(
                variant: Self.modelName,
                downloadBase: nil
            )
            if exists {
                modelState = .ready
            }
        }
    }

    func downloadModel() async {
        guard modelState == .notDownloaded || {
            if case .failed = modelState { return true }
            return false
        }() else { return }

        modelState = .downloading(progress: 0)
        downloadTask?.cancel()

        downloadTask = Task {
            do {
                let config = WhisperKitConfig(
                    model: Self.modelName,
                    verbose: false,
                    logLevel: .none,
                    prewarm: false,
                    load: true,
                    download: true
                )
                let kit = try await WhisperKit(config)
                if !Task.isCancelled {
                    self.whisperKit = kit
                    self.modelState = .ready
                }
            } catch {
                if !Task.isCancelled {
                    self.modelState = .failed(error.localizedDescription)
                }
            }
        }
        await downloadTask?.value
    }

    func deleteModel() {
        downloadTask?.cancel()
        whisperKit = nil
        Task {
            try? await WhisperKit.deleteModel(variant: Self.modelName, downloadBase: nil)
            self.modelState = .notDownloaded
        }
    }

    // MARK: - Transcription

    func transcribeTrack(
        _ track: AudioTrack,
        in audiobook: Audiobook,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> TrackLyrics {
        guard modelState == .ready else {
            throw LyricsError.modelNotReady
        }

        // Load WhisperKit instance if not in memory
        if whisperKit == nil {
            let config = WhisperKitConfig(
                model: Self.modelName,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: true,
                download: false
            )
            whisperKit = try await WhisperKit(config)
        }

        guard let kit = whisperKit else {
            throw LyricsError.modelNotReady
        }

        let fileURL = try fileURL(for: track, in: audiobook)

        let options = DecodingOptions(
            task: .transcribe,
            wordTimestamps: false,
            verbose: false
        )

        let results = try await kit.transcribe(
            audioPath: fileURL.path,
            decodeOptions: options
        ) { progress in
            Task { @MainActor in
                onProgress(Double(progress.timings.pipelineStart) / 1.0)
            }
            return true
        }

        // Unload model from memory after transcription to free RAM
        whisperKit = nil

        let segments = results.enumerated().compactMap { index, result -> LyricsSegment? in
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let start = result.segments.first?.start,
                  let end = result.segments.last?.end else { return nil }
            return LyricsSegment(
                id: index,
                text: text,
                start: Double(start),
                end: Double(end)
            )
        }

        let trackLyrics = TrackLyrics(
            trackID: track.id.uuidString,
            modelName: Self.modelName,
            createdAt: Date(),
            segments: segments
        )

        try saveCachedLyrics(trackLyrics, for: track, in: audiobook)
        return trackLyrics
    }

    // MARK: - Cache

    func loadCachedLyrics(for track: AudioTrack, in audiobook: Audiobook) -> TrackLyrics? {
        guard let cacheURL = lyricsURL(for: track, in: audiobook),
              let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(TrackLyrics.self, from: data)
    }

    func deleteCachedLyrics(for track: AudioTrack, in audiobook: Audiobook) {
        guard let cacheURL = lyricsURL(for: track, in: audiobook) else { return }
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func saveCachedLyrics(_ lyrics: TrackLyrics, for track: AudioTrack, in audiobook: Audiobook) throws {
        guard let cacheURL = lyricsURL(for: track, in: audiobook) else { return }
        let data = try JSONEncoder().encode(lyrics)
        try data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - Paths

    private func fileURL(for track: AudioTrack, in audiobook: Audiobook) throws -> URL {
        let folder = try audiobookFolderURL(for: audiobook.folderName)
        return folder.appendingPathComponent(track.storedFileName)
    }

    private func lyricsURL(for track: AudioTrack, in audiobook: Audiobook) -> URL? {
        guard let folder = try? audiobookFolderURL(for: audiobook.folderName) else { return nil }
        return folder.appendingPathComponent("\(track.storedFileName).lyrics.json")
    }

    private func audiobookFolderURL(for folderName: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport
            .appendingPathComponent("Audiobooks", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

// MARK: - Errors

enum LyricsError: LocalizedError {
    case modelNotReady
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            "WhisperKit model is not downloaded. Go to Settings to download it."
        case .transcriptionFailed(let msg):
            "Transcription failed: \(msg)"
        }
    }
}
