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

    init(
        audiobook: Audiobook,
        transcription: (any TranscriptionProviding)? = nil,
        audioExtractor: (any AudioExtracting)? = nil,
        recapProvider: (any RecapProviding)? = nil
    ) {
        self.audiobook = audiobook
        self.transcription = transcription ?? TranscriptionService()
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        self.recapProvider = recapProvider ?? RecapService()
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

        do {
            let tracks = audiobook.sortedTracks
            guard tracks.indices.contains(trackIndex) else { return }
            let track = tracks[trackIndex]
            let fileURL = try LibraryImportService.fileURL(for: track, in: audiobook)

            let startSeconds = max(0, progressTime - 200)
            let endSeconds = progressTime
            guard endSeconds > startSeconds else { return }

            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let authStatus = await transcription.requestAuthorization()
            guard authStatus == .authorized else {
                recapError = "Speech recognition not authorized."
                return
            }

            let transcript = try await transcription.transcribe(audioURL: audioURL)
            guard !transcript.isEmpty else {
                recapError = "Could not transcribe audio."
                return
            }

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
                anchorTrackIndex: trackIndex,
                anchorTime: progressTime
            )
            try? modelContext?.save()
            onSuccessfulRecap?()
        } catch {
            recapError = error.localizedDescription
        }
    }
}
