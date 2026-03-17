//
//  AudioPlayerManager.swift
//  Ebooker
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var currentAudiobook: Audiobook?
    @Published private(set) var currentTrack: AudioTrack?
    @Published private(set) var currentTrackIndex = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 1
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double = 1
    @Published var sleepTimerEndsAt: Date?
    @Published var playerErrorMessage: String?

    private let player = AVPlayer()
    private var timeObserverToken: Any?
    private var playbackEndedObserver: NSObjectProtocol?
    private var modelContext: ModelContext?
    private var lastPersistedTime: Double = -10
    private var resumeBacktrackSeconds: Double = ResumeBacktrackOption.oneMinute.rawValue
    private var skipBackSeconds: Double = SkipIntervalOption.thirty.rawValue
    private var skipForwardSeconds: Double = SkipIntervalOption.thirty.rawValue
    private var sleepTimerTask: Task<Void, Never>?
    private var isLoadingItem = false
    // Seconds of continuous listening required after a seek/jump before progress can advance.
    private static let progressSeekPenalty: Double = 180
    private var seekPenaltyRemaining: Double = 0

    private var backgroundObserver: NSObjectProtocol?

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        addPeriodicTimeObserver()
        observeTrackEnd()
        configureRemoteCommands()

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateProgressMarkerIfNeeded()
                self.persistPlayback(force: true)
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func applyPlaybackDefaults(resumeBacktrack: Double, skipBack: Double, skipForward: Double) {
        resumeBacktrackSeconds = resumeBacktrack
        skipBackSeconds = skipBack
        skipForwardSeconds = skipForward
    }

    var bookProgress: Double {
        currentAudiobook?.progress ?? 0
    }

    func startPlayback(for audiobook: Audiobook, autoplay: Bool = true) async {
        let resumeTime = audiobook.isFinished ? 0 : max(audiobook.currentTime - resumeBacktrackSeconds, 0)
        let trackIndex = audiobook.isFinished ? 0 : audiobook.currentTrackIndex
        await load(audiobook: audiobook, trackIndex: trackIndex, time: resumeTime, autoplay: autoplay)
    }

    func restart(_ audiobook: Audiobook) async {
        audiobook.currentTrackIndex = 0
        audiobook.currentTime = 0
        audiobook.isFinished = false
        audiobook.progressTrackIndex = nil
        audiobook.progressTime = nil
        audiobook.progressUpdatedAt = nil
        try? modelContext?.save()
        await load(audiobook: audiobook, trackIndex: 0, time: 0, autoplay: true)
    }

    func playTrack(at index: Int, in audiobook: Audiobook, time: Double = 0, autoplay: Bool = true) async {
        await load(audiobook: audiobook, trackIndex: index, time: time, autoplay: autoplay)
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        player.play()
        player.rate = Float(playbackRate)
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateProgressMarkerIfNeeded()
        persistPlayback(force: true)
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        seekPenaltyRemaining = Self.progressSeekPenalty
        let boundedTime = max(0, min(seconds, duration))
        let target = CMTime(seconds: boundedTime, preferredTimescale: 600)
        player.seek(to: target) { [weak self] finished in
            guard let self, finished else { return }
            Task { @MainActor in
                self.currentTime = boundedTime
                self.persistPlayback(force: true)
                self.updateNowPlayingInfo()
            }
        }
    }

    func skipBackward() {
        seek(to: currentTime - skipBackSeconds)
    }

    func skipForward() {
        if currentTime + skipForwardSeconds >= duration - 1, canGoToNextTrack {
            nextTrack()
            return
        }

        seek(to: currentTime + skipForwardSeconds)
    }

    var canGoToNextTrack: Bool {
        guard let audiobook = currentAudiobook else { return false }
        return currentTrackIndex + 1 < audiobook.sortedTracks.count
    }

    var canGoToPreviousTrack: Bool {
        currentTrackIndex > 0 || currentTime > 5
    }

    func nextTrack() {
        guard let audiobook = currentAudiobook, canGoToNextTrack else {
            markCurrentBookFinished()
            return
        }

        Task {
            await load(audiobook: audiobook, trackIndex: currentTrackIndex + 1, time: 0, autoplay: true)
        }
    }

    func previousTrack() {
        guard let audiobook = currentAudiobook else { return }

        if currentTime > 5 {
            seek(to: 0)
            return
        }

        let targetIndex = max(currentTrackIndex - 1, 0)
        Task {
            await load(audiobook: audiobook, trackIndex: targetIndex, time: 0, autoplay: true)
        }
    }

    func setPlaybackRate(_ newRate: Double) {
        playbackRate = newRate
        currentAudiobook?.playbackRate = newRate
        if isPlaying {
            player.rate = Float(newRate)
        }
        persistPlayback(force: true)
        updateNowPlayingInfo()
    }

    func setSleepTimer(seconds: Double?) {
        sleepTimerTask?.cancel()

        guard let seconds else {
            sleepTimerEndsAt = nil
            return
        }

        let endDate = Date().addingTimeInterval(seconds)
        sleepTimerEndsAt = endDate

        sleepTimerTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.pause()
                self.sleepTimerEndsAt = nil
            }
        }
    }

    private func load(audiobook: Audiobook, trackIndex: Int, time: Double, autoplay: Bool) async {
        guard audiobook.sortedTracks.indices.contains(trackIndex) else { return }
        guard let track = audiobook.sortedTracks[safe: trackIndex] else { return }

        seekPenaltyRemaining = Self.progressSeekPenalty
        isLoadingItem = true
        activateAudioSession()

        do {
            let fileURL = try LibraryImportService.fileURL(for: track, in: audiobook)
            let asset = AVURLAsset(url: fileURL)
            let item = AVPlayerItem(asset: asset)

            currentAudiobook = audiobook
            currentTrack = track
            currentTrackIndex = trackIndex
            currentTime = 0
            playbackRate = audiobook.playbackRate
            duration = track.duration > 0 ? track.duration : 1
            audiobook.currentTrackIndex = trackIndex
            audiobook.currentTime = time
            audiobook.lastPlayedAt = .now
            audiobook.isFinished = false
            lastPersistedTime = time

            player.replaceCurrentItem(with: item)

            if let loadedDuration = try? await asset.load(.duration), loadedDuration.seconds.isFinite, loadedDuration.seconds > 0 {
                duration = loadedDuration.seconds
                track.duration = loadedDuration.seconds
            }

            let startTime = max(0, min(time, duration))
            let target = CMTime(seconds: startTime, preferredTimescale: 600)
            await player.seek(to: target)
            currentTime = startTime
            lastPersistedTime = startTime
            isLoadingItem = false
            persistPlayback(force: true)

            if autoplay {
                play()
            } else {
                pause()
            }

            updateNowPlayingInfo()
        } catch {
            isLoadingItem = false
            playerErrorMessage = "Ebooker could not open this audio file."
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }

            Task { @MainActor in
                self.currentTime = max(time.seconds, 0)

                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }

                self.isPlaying = self.player.timeControlStatus == .playing
                if self.isPlaying, self.seekPenaltyRemaining > 0 {
                    self.seekPenaltyRemaining = max(0, self.seekPenaltyRemaining - 1)
                }
                self.updateProgressMarkerIfNeeded()
                self.persistPlayback()
                self.updateNowPlayingInfo()
            }
        }
    }

    private func observeTrackEnd() {
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard notification.object as? AVPlayerItem === self.player.currentItem else { return }

            Task { @MainActor in
                if self.canGoToNextTrack {
                    self.nextTrack()
                } else {
                    self.markCurrentBookFinished()
                }
            }
        }
    }

    private func updateProgressMarkerIfNeeded() {
        guard let audiobook = currentAudiobook else { return }
        guard seekPenaltyRemaining == 0 else { return }

        let currentOverall = audiobook.listenedDuration
        let storedOverall = audiobook.progressListenedDuration

        if currentOverall > storedOverall {
            audiobook.progressTrackIndex = currentTrackIndex
            audiobook.progressTime = min(currentTime, duration)
            audiobook.progressUpdatedAt = .now
        }
    }

    private func persistPlayback(force: Bool = false) {
        guard !isLoadingItem else { return }
        guard let audiobook = currentAudiobook else { return }

        audiobook.currentTrackIndex = currentTrackIndex
        audiobook.currentTime = min(currentTime, duration)
        audiobook.lastPlayedAt = .now
        audiobook.playbackRate = playbackRate
        audiobook.isFinished = false

        guard force || abs(audiobook.currentTime - lastPersistedTime) >= 5 else { return }

        do {
            try modelContext?.save()
            lastPersistedTime = audiobook.currentTime
        } catch {
            playerErrorMessage = "Playback progress could not be saved."
        }
    }

    private func markCurrentBookFinished() {
        guard let audiobook = currentAudiobook else { return }

        player.pause()
        isPlaying = false
        audiobook.isFinished = true
        audiobook.currentTrackIndex = max(audiobook.sortedTracks.count - 1, 0)
        audiobook.currentTime = duration
        audiobook.progressTrackIndex = audiobook.currentTrackIndex
        audiobook.progressTime = duration
        audiobook.progressUpdatedAt = .now
        currentTime = duration
        do {
            try modelContext?.save()
            lastPersistedTime = audiobook.currentTime
        } catch {
            playerErrorMessage = "Playback progress could not be saved."
        }
        updateNowPlayingInfo()
    }

    private static var hasConfiguredAudioSessionCategory = false

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            if !Self.hasConfiguredAudioSessionCategory {
                try session.setCategory(.playback, mode: .spokenAudio)
                Self.hasConfiguredAudioSessionCategory = true
            }
            try session.setActive(true)
        } catch {
            playerErrorMessage = "Audio could not be configured."
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.nextTrack()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.previousTrack()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self?.seek(to: event.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let audiobook = currentAudiobook, let track = currentTrack else { return }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyAlbumTitle: audiobook.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0
        ]

        if !audiobook.author.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = audiobook.author
        }

        if let coverArtData = audiobook.coverArtData, let image = UIImage(data: coverArtData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
