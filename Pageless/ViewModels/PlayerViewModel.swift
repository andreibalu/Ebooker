//
//  PlayerViewModel.swift
//  Pageless
//

import Foundation
import Speech
import SwiftData
import SwiftUI

/// Why a smart-save draft carries a fallback name instead of the model's. Shown calmly above
/// the name field: the passage is ordinary, the name is just simpler.
enum SmartSaveNotice: Equatable {
    case couldNotTranscribe
    case couldNotSummarize

    var message: String {
        switch self {
        case .couldNotTranscribe:
            "Unpaged couldn't transcribe this passage, so it suggested a simple name. You can change it."
        case .couldNotSummarize:
            "Apple Intelligence couldn't summarize this passage, so Unpaged suggested a simple name. You can change it."
        }
    }
}

@MainActor
@Observable
final class PlayerViewModel {
    // MARK: - Moment creation state

    var pendingMomentTime: Double?
    var pendingMomentTranscript: String?
    var pendingMomentAiGenerated = false
    var momentNameInput: String = "Saved Moment"
    var momentNoteInput: String = ""
    var isProcessingSmartSave = false
    var pendingSmartSaveNotice: SmartSaveNotice?
    var pendingCategories: [MomentCategory] = []
    var pendingQuoteLine: String?
    var pendingCharacters: [String] = []
    var pendingMood: MomentMood?

    // MARK: - Feedback state

    var momentSaved = false
    var progressMarked = false

    // MARK: - Dependencies

    // Context window around "now": the moment is what the user just heard, so weight
    // the window behind the playhead; future audio is noise/spoilers and costs time.
    static let momentContextBackSeconds: Double = 75
    static let momentContextForwardSeconds: Double = 15

    private let transcription: any TranscriptionProviding
    private let momentAnalyzer: any MomentAnalyzing
    private let audioExtractor: any AudioExtracting
    private let segmentTranscriber: any SegmentTranscribing

    init(
        transcription: (any TranscriptionProviding)? = nil,
        momentAnalyzer: (any MomentAnalyzing)? = nil,
        audioExtractor: (any AudioExtracting)? = nil,
        segmentTranscriber: (any SegmentTranscribing)? = nil
    ) {
        self.transcription = transcription ?? TranscriptionService()
        #if DEBUG
        let fixtureAnalyzer = momentAnalyzer == nil ? E2EFixtures.momentAnalyzer : nil
        let fixtureTranscriber = segmentTranscriber == nil ? E2EFixtures.momentTranscriber : nil
        #else
        let fixtureAnalyzer: (any MomentAnalyzing)? = nil
        let fixtureTranscriber: (any SegmentTranscribing)? = nil
        #endif
        if let momentAnalyzer = momentAnalyzer ?? fixtureAnalyzer {
            self.momentAnalyzer = momentAnalyzer
        } else if #available(iOS 26, *) {
            self.momentAnalyzer = MomentNamingService()
        } else {
            self.momentAnalyzer = UnavailableMomentAnalyzer()
        }
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        if let segmentTranscriber = segmentTranscriber ?? fixtureTranscriber {
            self.segmentTranscriber = segmentTranscriber
        } else if #available(iOS 26, *) {
            self.segmentTranscriber = SpeechAnalyzerTranscriptionService()
        } else {
            self.segmentTranscriber = UnavailableSegmentTranscriber()
        }
    }

    /// Loads model resources ahead of a likely smart save (called when the player opens).
    func prewarmSmartSave() {
        momentAnalyzer.prewarm()
    }

    // MARK: - Moment save workflow

    func saveMoment(
        player: AudioPlayerManager,
        useSmartSave: Bool,
        momentBacktrackSeconds: Double,
        onSuccessfulSmartAI: (() -> Void)? = nil
    ) {
        guard player.currentAudiobook != nil else { return }
        let savedTime = max(player.currentTime - momentBacktrackSeconds, 0)

        if useSmartSave {
            Task {
                await performSmartSave(
                    player: player,
                    savedTime: savedTime,
                    momentBacktrackSeconds: momentBacktrackSeconds,
                    onSuccessfulSmartAI: onSuccessfulSmartAI
                )
            }
        } else {
            resetMomentState()
            pendingMomentTime = savedTime
        }
    }

    private func performSmartSave(
        player: AudioPlayerManager,
        savedTime: Double,
        momentBacktrackSeconds: Double,
        onSuccessfulSmartAI: (() -> Void)?
    ) async {
        guard let audiobook = player.currentAudiobook,
              let track = player.currentTrack else { return }
        let context = AIPassageContext(
            bookTitle: audiobook.title,
            author: audiobook.author,
            chapterTitle: player.currentChapter?.title ?? track.title
        )

        guard !Task.isCancelled else { return }

        isProcessingSmartSave = true
        defer { isProcessingSmartSave = false }

        guard audiobook.isDownloaded,
              let fileURL = try? LibraryImportService.fileURL(for: track, in: audiobook) else {
            resetMomentState()
            pendingMomentTime = savedTime
            return
        }

        let transcript: String?
        do {
            transcript = try await obtainTranscript(
                fileURL: fileURL,
                currentTime: player.currentTime,
                duration: player.duration
            )
        } catch is CancellationError {
            // Cancellation means the user no longer wants this operation. Do not
            // open the legacy permission/export path or replace the pending state.
            return
        } catch {
            transcript = nil
        }

        guard !Task.isCancelled else { return }
        guard let transcript, !transcript.isEmpty else {
            applyFallback(transcript: nil, context: context, savedTime: savedTime, notice: .couldNotTranscribe)
            return
        }

        await applyAnalysis(
            transcript: transcript,
            context: context,
            savedTime: savedTime,
            onSuccessfulSmartAI: onSuccessfulSmartAI
        )
    }

    /// SpeechAnalyzer first (no permission, no export); legacy export +
    /// SFSpeechRecognizer fallback, which is the only path that needs authorization.
    /// Internal for tests.
    func obtainTranscript(fileURL: URL, currentTime: Double, duration: Double) async throws -> String? {
        try Task.checkCancellation()
        momentAnalyzer.prewarm() // overlap model load with transcription

        let start = max(0, currentTime - Self.momentContextBackSeconds)
        let end = min(duration, currentTime + Self.momentContextForwardSeconds)
        if end > start {
            do {
                let transcript = try await segmentTranscriber.transcribeSegment(
                    fileURL: fileURL, startSeconds: start, endSeconds: end
                )
                try Task.checkCancellation()
                if !transcript.isEmpty { return transcript }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A genuine primary-path failure is the only condition that can
                // enter the legacy permission/export fallback.
            }
        }

        try Task.checkCancellation()
        let authStatus = await transcription.requestAuthorization()
        try Task.checkCancellation()
        guard authStatus == .authorized else { return nil }
        do {
            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL, currentTime: currentTime, duration: duration
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }
            try Task.checkCancellation()
            let transcript = try await transcription.transcribe(audioURL: audioURL)
            try Task.checkCancellation()
            return transcript
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// Runs the analyzer and fills the pending-moment fields. Any failure but cancellation
    /// still opens the sheet, with a fallback name. Internal for tests.
    func applyAnalysis(
        transcript: String,
        context: AIPassageContext,
        savedTime: Double,
        onSuccessfulSmartAI: (() -> Void)? = nil
    ) async {
        guard !Task.isCancelled else { return }

        do {
            let analysis = try await momentAnalyzer.analyzeMoment(
                transcript: transcript,
                context: context
            )
            try Task.checkCancellation()
            momentNameInput = analysis.name
            momentNoteInput = analysis.note
            pendingMomentTranscript = transcript
            pendingMomentAiGenerated = true
            pendingCategories = analysis.categories
            pendingQuoteLine = analysis.quoteLine
            pendingCharacters = analysis.characters
            pendingMood = analysis.mood
            pendingSmartSaveNotice = nil
            pendingMomentTime = savedTime
            onSuccessfulSmartAI?()
        } catch is CancellationError {
            // A cancelled analysis must not present a partial fallback draft.
            return
        } catch {
            guard !Task.isCancelled else { return }
            applyFallback(transcript: transcript, context: context, savedTime: savedTime, notice: .couldNotSummarize)
        }
    }

    /// A draft named from the transcript, chapter and time, never "Saved Moment". The
    /// transcript is kept so moment search still finds the words.
    private func applyFallback(transcript: String?, context: AIPassageContext, savedTime: Double, notice: SmartSaveNotice) {
        let fallback = MomentFallbackNamer.analysis(
            transcript: transcript, chapterTitle: context.chapterTitle, time: savedTime
        )
        resetMomentState()
        momentNameInput = fallback.name
        pendingCharacters = fallback.characters
        pendingMomentTranscript = transcript
        pendingSmartSaveNotice = notice
        pendingMomentTime = savedTime
    }

    func commitMoment(player: AudioPlayerManager, modelContext: ModelContext) {
        guard let audiobook = player.currentAudiobook,
              let savedTime = pendingMomentTime else { return }

        let name = momentNameInput.trimmingCharacters(in: .whitespaces)
        let label = name.isEmpty ? "Saved Moment" : name
        let noteText = momentNoteInput.trimmingCharacters(in: .whitespaces)

        let moment = Moment(
            trackIndex: player.currentTrackIndex,
            time: savedTime,
            label: label,
            audiobook: audiobook,
            transcript: pendingMomentTranscript,
            aiGeneratedName: pendingMomentAiGenerated,
            notes: noteText.isEmpty ? nil : noteText,
            categories: pendingCategories,
            quoteLine: pendingQuoteLine,
            characters: pendingCharacters,
            mood: pendingMood
        )
        modelContext.insert(moment)
        try? modelContext.save()

        pendingMomentTime = nil
        pendingMomentTranscript = nil
        momentNoteInput = ""
        pendingCategories = []
        pendingQuoteLine = nil
        pendingCharacters = []
        pendingMood = nil
        pendingSmartSaveNotice = nil

        withAnimation(.spring(duration: 0.2)) { momentSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.3)) { self.momentSaved = false }
        }
    }

    func markProgress(player: AudioPlayerManager) {
        player.setProgressMarker()
        withAnimation(.spring(duration: 0.2)) { progressMarked = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(duration: 0.3)) { self.progressMarked = false }
        }
    }

    // MARK: - Private helpers

    private func resetMomentState() {
        momentNameInput = "Saved Moment"
        momentNoteInput = ""
        pendingMomentTranscript = nil
        pendingMomentAiGenerated = false
        pendingCategories = []
        pendingQuoteLine = nil
        pendingCharacters = []
        pendingMood = nil
        pendingSmartSaveNotice = nil
    }
}
