import Foundation
import SwiftData

@MainActor
@Observable
final class WelcomeBackRecapViewModel {
    static let returnInterval: TimeInterval = 3 * 86_400
    private let audiobook: Audiobook
    private let recapModel: AudiobookDetailViewModel
    private var cachedText: String?
    private var cachedHeadline: String?
    private var cachedTrack: Int?
    private var cachedTime: Double?
    var text: String?
    var headline: String?
    var isLoading = false
    var returnDate: Date?

    init(audiobook: Audiobook) {
        self.audiobook = audiobook
        var provider: (any RecapProviding)?
        var transcriber: (any SegmentTranscribing)?
        #if DEBUG
        if let fake = E2EFixtures.fakeRecapText {
            provider = E2EWelcomeRecapProvider(text: fake)
            transcriber = E2EWelcomeTranscriber()
        } else if let transcript = E2EFixtures.transcriptText {
            transcriber = E2EWelcomeTranscriber(text: transcript)
        }
        #endif
        recapModel = AudiobookDetailViewModel(audiobook: audiobook, recapProvider: provider,
                                             segmentTranscriber: transcriber)
        if audiobook.progressRecapMatchesProgress, let anchor = audiobook.progressRecapAnchorTime {
            cachedTrack = audiobook.progressRecapAnchorTrackIndex
            cachedTime = anchor
            cachedText = audiobook.progressRecapText
            cachedHeadline = audiobook.progressRecapHeadline
        }
    }

    private var dismissalKey: String { "welcomeBackDismissed.\(audiobook.id.uuidString)" }

    func dismiss() {
        if let returnDate {
            UserDefaults.standard.set(returnDate.timeIntervalSince1970, forKey: dismissalKey)
        }
        text = nil
        isLoading = false
    }

    func prepare(enabled: Bool, modelContext: ModelContext) async {
        text = nil
        guard enabled, !audiobook.isFinished, audiobook.isDownloaded,
              audiobook.progressListenedDuration >= 180,
              let date = audiobook.lastPlayedAt,
              let track = audiobook.progressTrackIndex, let position = audiobook.progressTime
        else { return }
        var interval = Self.returnInterval
        #if DEBUG
        if let value = E2EFixtures.argument("-e2e-welcome-threshold-days"), let days = Double(value), days >= 0 {
            interval = days * 86_400
        }
        #endif
        guard Date.now.timeIntervalSince(date) >= interval,
              UserDefaults.standard.double(forKey: dismissalKey) != date.timeIntervalSince1970
        else { return }
        returnDate = date
        if let cachedText, !cachedText.isEmpty, cachedTrack == track,
           let cachedTime, cachedTime <= position, position - cachedTime <= Audiobook.progressRecapTolerance {
            text = cachedText
            headline = cachedHeadline
            return
        }
        isLoading = true
        defer { isLoading = false }
        await recapModel.loadRecap(trackIndex: track, progressTime: position,
                                   includeProgressHeadline: true, requestSpeechAuthorization: false,
                                   modelContext: modelContext)
        guard !Task.isCancelled, audiobook.lastPlayedAt == date,
              audiobook.progressTrackIndex == track, audiobook.progressTime == position,
              UserDefaults.standard.double(forKey: dismissalKey) != date.timeIntervalSince1970,
              recapModel.recapError == nil, let recap = recapModel.recapText, !recap.isEmpty
        else { return }
        text = recap
        headline = recapModel.recapProgressHeadline
    }
}

