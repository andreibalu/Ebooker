//
//  AudiobookDetailViewModel.swift
//  Pageless
//

import Foundation
import Speech
import SwiftData

@MainActor
@Observable
final class AudiobookDetailViewModel {
    let audiobook: Audiobook

    // MARK: - Filter state

    var filterCategories: Set<MomentCategory> = []
    var filterCharacters: Set<String> = []
    var filterMoods: Set<MomentMood> = []

    // MARK: - Recap state

    var isLoadingRecap = false
    var recapText: String?
    /// Short headline for the progress row when Smart Summary + Short progress headline are enabled.
    var recapProgressHeadline: String?
    var recapError: String?

    // MARK: - Dependencies

    private let transcription: any TranscriptionProviding
    private let audioExtractor: any AudioExtracting
    private let recapProvider: any RecapProviding
    private let segmentTranscriber: any SegmentTranscribing

    init(
        audiobook: Audiobook,
        transcription: (any TranscriptionProviding)? = nil,
        audioExtractor: (any AudioExtracting)? = nil,
        recapProvider: (any RecapProviding)? = nil,
        segmentTranscriber: (any SegmentTranscribing)? = nil
    ) {
        self.audiobook = audiobook
        self.transcription = transcription ?? TranscriptionService()
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        if let recapProvider {
            self.recapProvider = recapProvider
        } else if #available(iOS 26, *) {
            self.recapProvider = RecapService()
        } else {
            self.recapProvider = UnavailableRecapProvider()
        }
        if let segmentTranscriber {
            self.segmentTranscriber = segmentTranscriber
        } else if #available(iOS 26, *) {
            self.segmentTranscriber = SpeechAnalyzerTranscriptionService()
        } else {
            self.segmentTranscriber = UnavailableSegmentTranscriber()
        }
        syncRecapFromAudiobook()
    }

    // MARK: - Computed properties

    var filteredMoments: [Moment] {
        let sorted = audiobook.moments.sorted { $0.createdAt > $1.createdAt }
        let base: [Moment]
        if hasActiveFilters {
            base = sorted.filter { moment in
                let matchesCategory = filterCategories.isEmpty || !filterCategories.isDisjoint(with: moment.categories)
                let matchesCharacter = filterCharacters.isEmpty || !filterCharacters.isDisjoint(with: Set(moment.characters.map { $0.lowercased() }))
                let matchesMood = filterMoods.isEmpty || (moment.mood.map { filterMoods.contains($0) } ?? false)
                return matchesCategory && matchesCharacter && matchesMood
            }
        } else {
            base = sorted
        }
        return base.filter(\.isPinned) + base.filter { !$0.isPinned }
    }

    var hasAiAnalyzedMoments: Bool {
        audiobook.moments.contains { !$0.categories.isEmpty || $0.mood != nil || !$0.characters.isEmpty }
    }

    var hasActiveFilters: Bool {
        !filterCategories.isEmpty || !filterCharacters.isEmpty || !filterMoods.isEmpty
    }

    // MARK: - Actions

    func clearFilters() {
        filterCategories.removeAll()
        filterCharacters.removeAll()
        filterMoods.removeAll()
    }

    /// Call when the detail screen appears so stale persisted recap is removed if the marker moved without a save path that cleared it.
    func reconcileStoredRecap(modelContext: ModelContext) {
        audiobook.discardProgressRecapIfAnchorMismatched()
        syncRecapFromAudiobook()
        try? modelContext.save()
    }

    private func syncRecapFromAudiobook() {
        guard
            let text = audiobook.progressRecapText,
            !text.isEmpty,
            let anchorTrack = audiobook.progressRecapAnchorTrackIndex,
            let anchorTime = audiobook.progressRecapAnchorTime,
            let progressTrack = audiobook.progressTrackIndex,
            let progressT = audiobook.progressTime,
            anchorTrack == progressTrack,
            anchorTime == progressT
        else {
            recapText = nil
            recapProgressHeadline = nil
            return
        }
        recapText = text
        recapProgressHeadline = audiobook.progressRecapHeadline
    }

    func loadRecap(
        trackIndex: Int,
        progressTime: Double,
        includeProgressHeadline: Bool,
        modelContext: ModelContext? = nil,
        onSuccessfulRecap: (() -> Void)? = nil
    ) async {
        isLoadingRecap = true
        defer { isLoadingRecap = false }

        let tracks = audiobook.sortedTracks
        guard tracks.indices.contains(trackIndex) else { return }
        guard let fileURL = try? LibraryImportService.fileURL(for: tracks[trackIndex], in: audiobook) else {
            recapError = "Audio for this book isn't on this iPhone."
            return
        }

        let startSeconds = max(0, progressTime - 200)
        guard progressTime > startSeconds else { return }

        guard let transcript = await obtainTranscript(
            fileURL: fileURL, startSeconds: startSeconds, endSeconds: progressTime
        ), !transcript.isEmpty else {
            if recapError == nil { recapError = "Could not transcribe audio." }
            return
        }

        await produceRecap(
            transcript: transcript,
            includeProgressHeadline: includeProgressHeadline,
            anchorTrackIndex: trackIndex,
            anchorTime: progressTime,
            modelContext: modelContext,
            onSuccessfulRecap: onSuccessfulRecap
        )
    }

    /// SpeechAnalyzer first (no permission, no export); legacy export +
    /// SFSpeechRecognizer fallback. Internal for tests.
    func obtainTranscript(fileURL: URL, startSeconds: Double, endSeconds: Double) async -> String? {
        if let transcript = try? await segmentTranscriber.transcribeSegment(
            fileURL: fileURL, startSeconds: startSeconds, endSeconds: endSeconds
        ), !transcript.isEmpty {
            return transcript
        }

        let authStatus = await transcription.requestAuthorization()
        guard authStatus == .authorized else {
            recapError = "Speech recognition not authorized."
            return nil
        }
        do {
            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL, startSeconds: startSeconds, endSeconds: endSeconds
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }
            return try await transcription.transcribe(audioURL: audioURL)
        } catch {
            return nil
        }
    }

    /// Runs the recap provider and persists the result. Internal for tests.
    func produceRecap(
        transcript: String,
        includeProgressHeadline: Bool,
        anchorTrackIndex: Int,
        anchorTime: Double,
        modelContext: ModelContext?,
        onSuccessfulRecap: (() -> Void)?
    ) async {
        do {
            let result = try await recapProvider.generateRecap(
                transcript: transcript,
                audiobookTitle: audiobook.title,
                includeProgressHeadline: includeProgressHeadline
            )
            recapText = result.recap
            recapProgressHeadline = result.progressHeadline
            recapError = nil
            audiobook.storeProgressRecap(
                text: result.recap,
                headline: result.progressHeadline,
                anchorTrackIndex: anchorTrackIndex,
                anchorTime: anchorTime
            )
            try? modelContext?.save()
            onSuccessfulRecap?()
        } catch let error as RecapError {
            recapError = error.errorDescription
        } catch {
            recapError = RecapError.generationFailed.errorDescription
        }
    }
}
