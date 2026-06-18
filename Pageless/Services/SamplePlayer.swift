//
//  SamplePlayer.swift
//  Pageless
//

import AVFoundation
import Foundation

@MainActor
@Observable
final class SamplePlayer {
    static let shared = SamplePlayer()

    enum State: Equatable {
        case idle
        case loading(bookId: String)
        case playing(bookId: String)
    }

    private(set) var state: State = .idle

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var stopTask: Task<Void, Never>?

    private init() {}

    func playSample(bookId: String, trackURL: URL) {
        stop()

        guard NetworkMonitor.shared.isConnected else { return }

        state = .loading(bookId: bookId)
        let asset = AVURLAsset(url: trackURL)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.volume = 1.0
        self.player = avPlayer

        // Observe when the item is ready to play.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    guard case .loading(let id) = self.state, id == bookId else { return }
                    let sampleStart = CMTime(seconds: Double(Self.sampleStartOffsetSeconds), preferredTimescale: 600)
                    avPlayer.seek(to: sampleStart, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            guard case .loading(let id) = self.state, id == bookId else { return }
                            self.state = .playing(bookId: bookId)
                            avPlayer.play()
                            self.stopTask?.cancel()
                            self.stopTask = Task { [weak self] in
                                try? await Task.sleep(for: .seconds(Self.sampleDurationSeconds))
                                guard !Task.isCancelled else { return }
                                self?.stop()
                            }
                        }
                    }
                case .failed:
                    self.stop()
                default:
                    break
                }
            }
        }

        // Duck other audio instead of interrupting
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

    }

    /// Offset from the beginning of the first track before sample playback starts.
    static let sampleStartOffsetSeconds: Int = 30

    /// Duration of the sample playback countdown, in seconds. Starts once the
    /// audio is actually ready to play (not while still loading).
    static let sampleDurationSeconds: Int = 20

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil

        if case .idle = state { return }
        state = .idle

        // Restore normal audio session (un-duck)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func isActive(for bookId: String) -> Bool {
        switch state {
        case .loading(let id), .playing(let id):
            return id == bookId
        case .idle:
            return false
        }
    }
}
