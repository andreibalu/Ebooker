//
//  AudioSessionInterruptionTests.swift
//  PagelessTests
//

import AVFoundation
import Foundation
import Testing
@testable import Pageless

/// Tests that AudioPlayerManager correctly responds to AVAudioSession interruptions
/// (e.g. Siri activating its microphone, incoming calls).
@MainActor
struct AudioSessionInterruptionTests {

    // MARK: - Helpers

    private func postInterruption(type: AVAudioSession.InterruptionType,
                                  options: AVAudioSession.InterruptionOptions = []) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: UInt(type.rawValue)
        ]
        if !options.isEmpty {
            userInfo[AVAudioSessionInterruptionOptionKey] = UInt(options.rawValue)
        }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }

    /// Waits long enough for the notification dispatch and inner @MainActor Task to complete.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms
    }

    // MARK: - .began

    @Test func interruptionBeganPausesWhenPlaying() async throws {
        let player = AudioPlayerManager()
        player.play()
        #expect(player.isPlaying == true)

        postInterruption(type: .began)
        try await settle()

        #expect(player.isPlaying == false)
    }

    // Catches: an interruption whose notification arrives after AVPlayer paused itself (so
    // `isPlaying` is already false) recording no break, so Play after it resumes with no rewind.
    @Test func interruptionBeganRightAfterPlaybackStoppedStillRecordsTheBreak() async throws {
        let player = AudioPlayerManager()
        player.seedUnitTestPlayingObserved(at: Date().addingTimeInterval(-1))
        #expect(!player.isPlaying)
        #expect(!player.hasSmartRewindAnchorForTesting)

        postInterruption(type: .began)
        try await settle()

        #expect(player.hasSmartRewindAnchorForTesting)
    }

    @Test func interruptionBeganOnASilentBookRecordsNoBreak() async throws {
        let player = AudioPlayerManager()
        player.seedUnitTestPlayingObserved(at: Date().addingTimeInterval(-60))

        postInterruption(type: .began)
        try await settle()

        #expect(!player.hasSmartRewindAnchorForTesting)
    }

    // MARK: - .ended

    @Test func interruptionEndedResumesWhenShouldResumeSet() {
        var controller = AudioSessionInterruptionController()

        #expect(controller.action(for: .began, options: [], isPlaying: true) == .pause)
        #expect(controller.action(for: .ended, options: .shouldResume, isPlaying: false) == .resume)
    }

    @Test func interruptionEndedDoesNotResumeWithoutShouldResume() async throws {
        let player = AudioPlayerManager()
        player.play()

        postInterruption(type: .began)
        try await settle()

        postInterruption(type: .ended) // no .shouldResume
        try await settle()

        #expect(player.isPlaying == false)
    }

    @Test func interruptionEndedWithoutPriorBeganDoesNotStartPlayback() {
        var controller = AudioSessionInterruptionController()

        #expect(controller.action(for: .ended, options: .shouldResume, isPlaying: false) == .none)
    }
}
