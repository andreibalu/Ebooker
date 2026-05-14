//
//  ComebackPromptCoordinator.swift
//  Pageless
//

import Foundation
import OSLog
import SwiftData
import SwiftUI

private let comebackLog = Logger(subsystem: "andreibaludev.Pageless", category: "ComebackRecap")

/// Inputs evaluated by `ComebackPromptCoordinator.shouldOffer` — kept as a plain
/// struct so the decision is pure and testable without standing up an Audiobook
/// or the entitlement store.
struct ComebackPromptInputs {
    var lastPlayedAt: Date?
    var hasProgressPosition: Bool
    var useLocalAIFeatures: Bool
    var useComebackRecap: Bool
    var canUseAIFeatures: Bool
    var capabilityAvailable: Bool
}

/// Drives the welcome-back recap prompt across the foreground SwiftUI surface,
/// CarPlay, and Siri-launched flows.
@MainActor
final class ComebackPromptCoordinator: ObservableObject {
    enum LaunchSource { case foreground, carPlay, siri }

    /// Drives the SwiftUI sheet in `ContentView`. CarPlay and Siri sources do
    /// not publish to this — they own their own UI/voice presentation.
    struct PendingPrompt: Identifiable {
        let id = UUID()
        let audiobookID: UUID
        var recap: ComebackRecapResult?
        var isLoading: Bool
        var errorMessage: String?
    }

    @Published var pendingPrompt: PendingPrompt?

    static let defaultStaleThreshold: TimeInterval = 4 * 60 * 60

    private let audioExtractor: any AudioExtracting
    private let transcription: any TranscriptionProviding
    private let recapProvider: any RecapProviding
    private let staleThreshold: TimeInterval

    /// Closure to run when the user has answered (Yes or Skip). Cleared after each
    /// presentation so call sites can each supply their own playback semantics
    /// (start vs progress-bookmark).
    private var pendingPlaybackHandler: (@MainActor (Audiobook) async -> Void)?
    /// Injected by the app to consume an AI trial credit on successful recap generation.
    private var consumeTrialUseHandler: (@MainActor () -> Void)?

    init(
        audioExtractor: (any AudioExtracting)? = nil,
        transcription: (any TranscriptionProviding)? = nil,
        recapProvider: (any RecapProviding)? = nil,
        staleThreshold: TimeInterval = ComebackPromptCoordinator.defaultStaleThreshold
    ) {
        self.audioExtractor = audioExtractor ?? AudioExtractionService()
        self.transcription = transcription ?? TranscriptionService()
        self.recapProvider = recapProvider ?? RecapService()
        self.staleThreshold = staleThreshold
    }

    func configure(consumeTrialUse: @escaping @MainActor () -> Void) {
        self.consumeTrialUseHandler = consumeTrialUse
    }

    /// Pure decision — whether the welcome-back prompt is eligible to fire.
    /// Threshold defaults to 4 hours and is overridable for tests.
    static func shouldOffer(
        _ inputs: ComebackPromptInputs,
        now: Date = .now,
        threshold: TimeInterval = ComebackPromptCoordinator.defaultStaleThreshold
    ) -> Bool {
        guard inputs.useLocalAIFeatures,
              inputs.useComebackRecap,
              inputs.canUseAIFeatures,
              inputs.capabilityAvailable,
              inputs.hasProgressPosition,
              let lastPlayed = inputs.lastPlayedAt
        else { return false }
        return now.timeIntervalSince(lastPlayed) >= threshold
    }

    /// Reads the current AppStorage settings + entitlement + capability and packs
    /// them into a `ComebackPromptInputs` value for the given audiobook.
    static func currentInputs(for audiobook: Audiobook, entitlement: AIEntitlementStore) -> ComebackPromptInputs {
        let defaults = UserDefaults.standard
        return ComebackPromptInputs(
            lastPlayedAt: audiobook.lastPlayedAt,
            hasProgressPosition: audiobook.hasProgressPosition,
            useLocalAIFeatures: defaults.bool(forKey: "useLocalAIFeatures"),
            useComebackRecap: defaults.bool(forKey: "useComebackRecap"),
            canUseAIFeatures: entitlement.canUseAIFeatures,
            capabilityAvailable: AppleIntelligenceCapability.isSmartNamingAvailable
        )
    }

    /// Generates the comeback recap for an audiobook using the same 200-second
    /// audio window ending at `progressTime` that the in-app recap uses.
    /// Returns `nil` if generation fails for any reason (caller should resume playback unprompted).
    func generateRecap(for audiobook: Audiobook) async -> ComebackRecapResult? {
        guard let trackIndex = audiobook.progressTrackIndex,
              let progressTime = audiobook.progressTime
        else { return nil }

        let tracks = audiobook.sortedTracks
        guard tracks.indices.contains(trackIndex) else { return nil }
        let track = tracks[trackIndex]

        do {
            let fileURL = try LibraryImportService.fileURL(for: track, in: audiobook)
            let startSeconds = max(0, progressTime - 200)
            let endSeconds = progressTime
            guard endSeconds > startSeconds else { return nil }

            let audioURL = try await audioExtractor.extractSegment(
                from: fileURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let authStatus = await transcription.requestAuthorization()
            guard authStatus == .authorized else { return nil }

            let transcript = try await transcription.transcribe(audioURL: audioURL)
            guard !transcript.isEmpty else { return nil }

            let result = try await recapProvider.generateComebackRecap(
                transcript: transcript,
                audiobookTitle: audiobook.title
            )
            consumeTrialUseHandler?()
            return result
        } catch {
            comebackLog.error("comeback recap failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Foreground SwiftUI flow

    /// Wraps a playback start. If eligible, presents the SwiftUI prompt sheet and
    /// defers playback until Yes/Skip. Otherwise runs `playback` immediately.
    func wrapPlaybackStart(
        for audiobook: Audiobook,
        entitlement: AIEntitlementStore,
        playback: @escaping @MainActor (Audiobook) async -> Void
    ) {
        let inputs = Self.currentInputs(for: audiobook, entitlement: entitlement)
        guard Self.shouldOffer(inputs, threshold: staleThreshold) else {
            Task { @MainActor in
                await playback(audiobook)
            }
            return
        }

        pendingPlaybackHandler = playback
        pendingPrompt = PendingPrompt(
            audiobookID: audiobook.id,
            recap: nil,
            isLoading: true,
            errorMessage: nil
        )

        Task { @MainActor in
            let result = await generateRecap(for: audiobook)
            guard pendingPrompt?.audiobookID == audiobook.id else { return }
            if let result {
                pendingPrompt?.recap = result
                pendingPrompt?.isLoading = false
            } else {
                pendingPrompt?.errorMessage = "Couldn't build a recap."
                pendingPrompt?.isLoading = false
            }
        }
    }

    /// User tapped Start / Skip — clears the prompt and runs the deferred playback.
    func resolveForegroundPrompt(audiobook: Audiobook) {
        pendingPrompt = nil
        let handler = pendingPlaybackHandler
        pendingPlaybackHandler = nil
        Task { @MainActor in
            await handler?(audiobook)
        }
    }
}
