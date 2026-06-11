//
//  PlayerViewModel.swift
//  Pageless
//

import Foundation
import Speech
import SwiftData
import SwiftUI

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
    var pendingSmartSaveUnsafeWarning = false
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
        if let momentAnalyzer {
            self.momentAnalyzer = momentAnalyzer
        } else if #available(iOS 26, *) {
            self.momentAnalyzer = MomentNamingService()
        } else {
            self.momentAnalyzer = UnavailableMomentAnalyzer()
        }
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        if let segmentTranscriber {
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

        isProcessingSmartSave = true
        defer { isProcessingSmartSave = false }

        guard let fileURL = try? LibraryImportService.fileURL(for: track, in: audiobook),
              let transcript = await obtainTranscript(
                  fileURL: fileURL,
                  currentTime: player.currentTime,
                  duration: player.duration
              ),
              !transcript.isEmpty
        else {
            resetMomentState()
            pendingMomentTime = savedTime
            return
        }

        await applyAnalysis(
            transcript: transcript,
            audiobookTitle: audiobook.title,
            savedTime: savedTime,
            onSuccessfulSmartAI: onSuccessfulSmartAI
        )
    }

    /// SpeechAnalyzer first (no permission, no export); legacy export +
    /// SFSpeechRecognizer fallback, which is the only path that needs authorization.
    /// Internal for tests.
    func obtainTranscript(fileURL: URL, currentTime: Double, duration: Double) async -> String? {
        momentAnalyzer.prewarm() // overlap model load with transcription

        let start = max(0, currentTime - Self.momentContextBackSeconds)
        let end = min(duration, currentTime + Self.momentContextForwardSeconds)
        if end > start,
           let transcript = try? await segmentTranscriber.transcribeSegment(
               fileURL: fileURL, startSeconds: start, endSeconds: end
           ),
           !transcript.isEmpty {
            return transcript
        }

        let authStatus = await transcription.requestAuthorization()
        guard authStatus == .authorized else { return nil }
        do {
            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL, currentTime: currentTime, duration: duration
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }
            return try await transcription.transcribe(audioURL: audioURL)
        } catch {
            return nil
        }
    }

    /// Runs the analyzer and fills the pending-moment fields. Internal for tests.
    func applyAnalysis(
        transcript: String,
        audiobookTitle: String,
        savedTime: Double,
        onSuccessfulSmartAI: (() -> Void)? = nil
    ) async {
        do {
            let analysis = try await momentAnalyzer.analyzeMoment(
                transcript: transcript,
                audiobookTitle: audiobookTitle
            )
            momentNameInput = analysis.name
            momentNoteInput = analysis.note
            pendingMomentTranscript = transcript
            pendingMomentAiGenerated = true
            pendingCategories = analysis.categories
            pendingQuoteLine = analysis.quoteLine
            pendingCharacters = analysis.characters
            pendingMood = analysis.mood
            pendingSmartSaveUnsafeWarning = false
            pendingMomentTime = savedTime
            onSuccessfulSmartAI?()
        } catch {
            resetMomentState()
            pendingMomentTranscript = transcript
            pendingSmartSaveUnsafeWarning = (error as? MomentNamingError) == .unsafeContent
            pendingMomentTime = savedTime
        }
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
        pendingSmartSaveUnsafeWarning = false

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
        pendingSmartSaveUnsafeWarning = false
    }
}
