//
//  AudiobookDetailViewModel.swift
//  Ebooker
//

import Foundation
import Speech

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
    }

    // MARK: - Computed properties

    var filteredMoments: [Moment] {
        let sorted = audiobook.moments.sorted { $0.createdAt > $1.createdAt }
        guard hasActiveFilters else { return sorted }
        return sorted.filter { moment in
            let matchesCategory = filterCategories.isEmpty || !filterCategories.isDisjoint(with: moment.categories)
            let matchesCharacter = filterCharacters.isEmpty || !filterCharacters.isDisjoint(with: Set(moment.characters.map { $0.lowercased() }))
            let matchesMood = filterMoods.isEmpty || (moment.mood.map { filterMoods.contains($0) } ?? false)
            return matchesCategory && matchesCharacter && matchesMood
        }
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

    func loadRecap(trackIndex: Int, progressTime: Double) async {
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

            let recap = try await recapProvider.generateRecap(
                transcript: transcript,
                audiobookTitle: audiobook.title
            )
            recapText = recap
            recapError = nil
        } catch {
            recapError = error.localizedDescription
        }
    }
}
