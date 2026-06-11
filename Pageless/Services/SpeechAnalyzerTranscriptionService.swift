//
//  SpeechAnalyzerTranscriptionService.swift
//  Pageless
//

import AVFoundation
import Foundation
import Speech

/// Transcribes a time range of an audio file with the iOS 26 SpeechAnalyzer API.
/// Compared with the legacy export + SFSpeechRecognizer path: no temp file, no
/// re-encode, no speech-recognition permission, no audio-length cap, punctuated
/// output, faster than realtime.
@available(iOS 26, *)
struct SpeechAnalyzerTranscriptionService: SegmentTranscribing {
    /// ~1.5 s of audio at 44.1 kHz per buffer handed to the analyzer.
    private static let chunkFrames: AVAudioFrameCount = 65_536

    func transcribeSegment(fileURL: URL, startSeconds: Double, endSeconds: Double) async throws -> String {
        guard endSeconds > startSeconds else { throw SegmentTranscriptionError.invalidRange }

        let locale = try await Self.resolveLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw SegmentTranscriptionError.audioUnreadable
        }

        let fileFormat = audioFile.processingFormat
        let sampleRate = fileFormat.sampleRate
        guard sampleRate > 0, audioFile.length > 0 else { throw SegmentTranscriptionError.audioUnreadable }

        let startFrame = AVAudioFramePosition(max(0, startSeconds) * sampleRate)
        let endFrame = min(AVAudioFramePosition(endSeconds * sampleRate), audioFile.length)
        guard endFrame > startFrame, startFrame < audioFile.length else {
            throw SegmentTranscriptionError.invalidRange
        }

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: fileFormat
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        let feeder = AudioSegmentFeeder(
            file: audioFile,
            startFrame: startFrame,
            endFrame: endFrame,
            chunkFrames: Self.chunkFrames,
            outputFormat: analyzerFormat
        )
        let feedTask = Task.detached(priority: .userInitiated) {
            try feeder.feed(into: inputBuilder)
        }

        let resultsTask = Task {
            var pieces: [String] = []
            for try await result in transcriber.results {
                pieces.append(String(result.text.characters))
            }
            return pieces.joined(separator: " ")
        }

        do {
            _ = try await analyzer.analyzeSequence(inputSequence)
            try await feedTask.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            feedTask.cancel()
            resultsTask.cancel()
            throw SegmentTranscriptionError.analysisFailed
        }

        let text: String
        do {
            text = try await resultsTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw SegmentTranscriptionError.analysisFailed
        }
        guard !text.isEmpty else { throw SegmentTranscriptionError.emptyResult }
        return text
    }

    /// Installed locales first (no download), then supported (one-time asset
    /// download); exact match → same language → English; else unavailable.
    static func resolveLocale() async throws -> Locale {
        if let match = bestMatch(in: await SpeechTranscriber.installedLocales, for: Locale.current) {
            return match
        }
        if let match = bestMatch(in: await SpeechTranscriber.supportedLocales, for: Locale.current) {
            return match
        }
        throw SegmentTranscriptionError.localeUnavailable
    }

    static func bestMatch(in locales: [Locale], for current: Locale) -> Locale? {
        if let exact = locales.first(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) {
            return exact
        }
        if let sameLanguage = locales.first(where: { $0.language.languageCode == current.language.languageCode }) {
            return sameLanguage
        }
        return locales.first(where: { $0.language.languageCode == Locale.LanguageCode("en") })
    }
}

/// Reads the requested frame range chunk-by-chunk and feeds it to the analyzer,
/// converting to the analyzer's preferred format when it differs from the file's.
/// Class (not struct) so the non-Sendable AVAudioFile/AVAudioConverter are confined
/// to the single feeding task. `nonisolated` opts out of the project's MainActor
/// default isolation — feeding must run on the detached task, not the main actor.
@available(iOS 26, *)
private nonisolated final class AudioSegmentFeeder: @unchecked Sendable {
    private let file: AVAudioFile
    private let startFrame: AVAudioFramePosition
    private let endFrame: AVAudioFramePosition
    private let chunkFrames: AVAudioFrameCount
    private let outputFormat: AVAudioFormat?
    private let converter: AVAudioConverter?

    init(
        file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        chunkFrames: AVAudioFrameCount,
        outputFormat: AVAudioFormat?
    ) {
        self.file = file
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.chunkFrames = chunkFrames
        self.outputFormat = outputFormat
        if let outputFormat, outputFormat != file.processingFormat {
            self.converter = AVAudioConverter(from: file.processingFormat, to: outputFormat)
        } else {
            self.converter = nil
        }
    }

    func feed(into builder: AsyncStream<AnalyzerInput>.Continuation) throws {
        defer { builder.finish() }
        file.framePosition = startFrame
        var remaining = AVAudioFrameCount(endFrame - startFrame)

        while remaining > 0 {
            try Task.checkCancellation()
            let frames = min(remaining, chunkFrames)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                throw SegmentTranscriptionError.audioUnreadable
            }
            try file.read(into: buffer, frameCount: frames)
            guard buffer.frameLength > 0 else { break }
            remaining -= buffer.frameLength
            builder.yield(AnalyzerInput(buffer: try converted(buffer)))
        }
    }

    private func converted(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter, let outputFormat else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SegmentTranscriptionError.audioUnreadable
        }
        var fed = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError {
            throw conversionError
        }
        return outBuffer
    }
}
