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
    var pendingCategories: [MomentCategory] = []
    var pendingQuoteLine: String?
    var pendingCharacters: [String] = []
    var pendingMood: MomentMood?

    // MARK: - Feedback state

    var momentSaved = false
    var progressMarked = false

    // MARK: - Dependencies

    private let transcription: any TranscriptionProviding
    private let momentAnalyzer: any MomentAnalyzing
    private let audioExtractor: any AudioExtracting

    init(
        transcription: (any TranscriptionProviding)? = nil,
        momentAnalyzer: (any MomentAnalyzing)? = nil,
        audioExtractor: (any AudioExtracting)? = nil
    ) {
        self.transcription = transcription ?? TranscriptionService()
        self.momentAnalyzer = momentAnalyzer ?? MomentNamingService()
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
    }

    // MARK: - Moment save workflow

    func saveMoment(
        player: AudioPlayerManager,
        useSmartSave: Bool,
        momentBacktrackSeconds: Double
    ) {
        guard player.currentAudiobook != nil else { return }
        let savedTime = max(player.currentTime - momentBacktrackSeconds, 0)

        if useSmartSave {
            Task { await performSmartSave(player: player, savedTime: savedTime, momentBacktrackSeconds: momentBacktrackSeconds) }
        } else {
            resetMomentState()
            pendingMomentTime = savedTime
        }
    }

    private func performSmartSave(
        player: AudioPlayerManager,
        savedTime: Double,
        momentBacktrackSeconds: Double
    ) async {
        guard let audiobook = player.currentAudiobook,
              let track = player.currentTrack else { return }

        let authStatus = await transcription.requestAuthorization()
        guard authStatus == .authorized else {
            resetMomentState()
            pendingMomentTime = max(player.currentTime - momentBacktrackSeconds, 0)
            return
        }

        isProcessingSmartSave = true
        defer { isProcessingSmartSave = false }

        do {
            let fileURL = try LibraryImportService.fileURL(for: track, in: audiobook)
            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL,
                currentTime: player.currentTime,
                duration: player.duration
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let transcript = try await transcription.transcribe(audioURL: audioURL)
            if transcript.isEmpty {
                resetMomentState()
                pendingMomentTime = savedTime
            } else if let analysis = try? await momentAnalyzer.analyzeMoment(
                transcript: transcript,
                audiobookTitle: audiobook.title
            ) {
                momentNameInput = analysis.name
                momentNoteInput = analysis.note
                pendingMomentTranscript = transcript
                pendingMomentAiGenerated = true
                pendingCategories = analysis.categories
                pendingQuoteLine = analysis.quoteLine
                pendingCharacters = analysis.characters
                pendingMood = analysis.mood
                pendingMomentTime = savedTime
            } else {
                resetMomentState()
                pendingMomentTranscript = transcript
                pendingMomentTime = savedTime
            }
        } catch {
            resetMomentState()
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
    }
}
