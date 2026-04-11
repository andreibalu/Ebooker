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

        // Observe when the item is ready to play
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.state = .playing(bookId: bookId)
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

        avPlayer.play()

        // Auto-stop after 10 seconds
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

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
