//
//  AudioPlayerManager.swift
//  Pageless
//

import AVFoundation
import Combine
import MediaPlayer
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    /// Shared with `PlayerView` and CarPlay playback-rate controls.
    static let supportedPlaybackRates: [Double] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0]
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
    private var resumeBacktrackSeconds: Double = ResumeBacktrackOption.oneMinute.rawValue
    private var skipBackSeconds: Double = SkipIntervalOption.thirty.rawValue
    private var skipForwardSeconds: Double = SkipIntervalOption.thirty.rawValue
    /// When true, the next Continue / library Resume / progress bookmark play may apply On Resume backtrack. Resets each app launch.
    private var resumeBacktrackAvailableThisLaunch = true
    private var sleepTimerTask: Task<Void, Never>?
    private var isLoadingItem = false
    private var backgroundObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    let persistence = PlaybackPersistence()
    private let nowPlaying = NowPlayingUpdater()

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

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            Task { @MainActor in
                switch type {
                case .began:
                    if self.isPlaying { self.pause() }
                case .ended:
                    if let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                       AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                        self.play()
                    }
                default:
                    break
                }
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Seeds audiobook/track index/time for unit tests without loading media.
    func seedUnitTestPlaybackState(
        audiobook: Audiobook?,
        track: AudioTrack?,
        trackIndex: Int,
        currentTime: Double,
        duration: Double = 60
    ) {
        currentAudiobook = audiobook
        currentTrack = track
        currentTrackIndex = trackIndex
        self.currentTime = currentTime
        self.duration = duration
    }

    func applyPlaybackDefaults(resumeBacktrack: Double, skipBack: Double, skipForward: Double) {
        resumeBacktrackSeconds = resumeBacktrack
        skipBackSeconds = skipBack
        skipForwardSeconds = skipForward
        configureRemoteCommands()
    }

    var bookProgress: Double {
        currentAudiobook?.progress ?? 0
    }

    func startPlayback(for audiobook: Audiobook, autoplay: Bool = true) async {
        let trackIndex = audiobook.isFinished ? 0 : audiobook.currentTrackIndex
        let baseTime = audiobook.isFinished ? 0 : audiobook.currentTime
        let applyBacktrack = resumeBacktrackAvailableThisLaunch && !audiobook.isFinished
        let resumeTime = max(baseTime - (applyBacktrack ? resumeBacktrackSeconds : 0), 0)
        resumeBacktrackAvailableThisLaunch = false
        await load(audiobook: audiobook, trackIndex: trackIndex, time: resumeTime, autoplay: autoplay)
    }

    /// Starts like tapping “Your progress” on the book detail: uses the saved progress marker when set (with On Resume backtrack), otherwise last playback position.
    func startPlaybackFromSavedProgress(for audiobook: Audiobook, autoplay: Bool = true) async {
        switch AudiobookSavedProgressResume.startChoice(for: audiobook) {
        case .useProgressBookmark(let idx, let t):
            await playProgressBookmark(at: idx, in: audiobook, time: t, autoplay: autoplay)
        case .useStandardStartPlayback:
            await startPlayback(for: audiobook, autoplay: autoplay)
        }
    }

    /// Seeks to the saved progress marker time exactly (no resume backtrack). Use when the user scrubbed away and wants to snap back.
    func jumpToSavedProgressMarker(in audiobook: Audiobook) async {
        guard audiobook.hasProgressPosition,
              let idx = audiobook.progressTrackIndex,
              let t = audiobook.progressTime
        else { return }
        await playTrack(at: idx, in: audiobook, time: t, autoplay: true)
    }

    func restart(_ audiobook: Audiobook) async {
        audiobook.currentTrackIndex = 0
        audiobook.currentTime = 0
        audiobook.isFinished = false
        try? modelContext?.save()
        await load(audiobook: audiobook, trackIndex: 0, time: 0, autoplay: true)
    }

    func playTrack(at index: Int, in audiobook: Audiobook, time: Double = 0, autoplay: Bool = true) async {
        await load(audiobook: audiobook, trackIndex: index, time: time, autoplay: autoplay)
    }

    /// Like `playTrack`, but shares session-scoped On Resume backtrack with `startPlayback` (Your progress row).
    func playProgressBookmark(at index: Int, in audiobook: Audiobook, time: Double, autoplay: Bool = true) async {
        let back = resumeBacktrackAvailableThisLaunch ? resumeBacktrackSeconds : 0
        let t = max(time - back, 0)
        resumeBacktrackAvailableThisLaunch = false
        await load(audiobook: audiobook, trackIndex: index, time: t, autoplay: autoplay)
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
        persistence.seekPenaltyRemaining = PlaybackPersistence.progressSeekPenalty
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

    func setProgressMarker() {
        guard let audiobook = currentAudiobook else { return }
        let oldTrack = audiobook.progressTrackIndex
        let oldTime = audiobook.progressTime
        let newTrack = currentTrackIndex
        let newTime = min(currentTime, duration)
        let markerChanged =
            oldTrack != newTrack
            || oldTime.map { abs($0 - newTime) > 0.001 } ?? true
        if markerChanged {
            audiobook.clearProgressRecap()
        }
        audiobook.progressTrackIndex = newTrack
        audiobook.progressTime = newTime
        audiobook.progressUpdatedAt = .now
        persistence.seekPenaltyRemaining = 0
        try? modelContext?.save()
    }

    // MARK: - Private

    private func load(audiobook: Audiobook, trackIndex: Int, time: Double, autoplay: Bool) async {
        guard audiobook.sortedTracks.indices.contains(trackIndex) else { return }
        guard let track = audiobook.sortedTracks[safe: trackIndex] else { return }

        persistence.seekPenaltyRemaining = PlaybackPersistence.progressSeekPenalty
        isLoadingItem = true
        activateAudioSession()

        do {
            let assetURL: URL
            if audiobook.isDownloaded {
                assetURL = try LibraryImportService.fileURL(for: track, in: audiobook)
            } else if let remoteURL = track.remoteURL {
                guard NetworkMonitor.shared.isConnected else {
                    isLoadingItem = false
                    playerErrorMessage = "You're offline. Download this book to listen without internet."
                    return
                }
                assetURL = remoteURL
            } else {
                isLoadingItem = false
                playerErrorMessage = "No audio source available for this track."
                return
            }
            let asset = AVURLAsset(url: assetURL)
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
            persistence.lastPersistedTime = time

            player.replaceCurrentItem(with: item)

            if let loadedDuration = try? await asset.load(.duration), loadedDuration.seconds.isFinite, loadedDuration.seconds > 0 {
                duration = loadedDuration.seconds
                track.duration = loadedDuration.seconds
            }

            let startTime = max(0, min(time, duration))
            let target = CMTime(seconds: startTime, preferredTimescale: 600)
            await player.seek(to: target)
            currentTime = startTime
            persistence.lastPersistedTime = startTime
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
            playerErrorMessage = "Unpaged could not open this audio file."
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
                if self.isPlaying, self.persistence.seekPenaltyRemaining > 0 {
                    self.persistence.seekPenaltyRemaining = max(0, self.persistence.seekPenaltyRemaining - 1)
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
        persistence.updateProgressIfNeeded(
            audiobook: audiobook,
            currentTrackIndex: currentTrackIndex,
            currentTime: currentTime,
            duration: duration
        )
    }

    private func persistPlayback(force: Bool = false) {
        guard !isLoadingItem, let audiobook = currentAudiobook else { return }
        persistence.persist(
            audiobook: audiobook,
            trackIndex: currentTrackIndex,
            time: currentTime,
            duration: duration,
            rate: playbackRate,
            force: force,
            context: modelContext
        )
    }

    private func markCurrentBookFinished() {
        guard let audiobook = currentAudiobook else { return }
        player.pause()
        isPlaying = false
        let trackIndex = max(audiobook.sortedTracks.count - 1, 0)
        persistence.markFinished(
            audiobook: audiobook,
            trackIndex: trackIndex,
            duration: duration,
            context: modelContext
        )
        currentTime = duration
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

    private func updateNowPlayingInfo() {
        guard let audiobook = currentAudiobook, let track = currentTrack else { return }
        nowPlaying.update(
            audiobook: audiobook,
            track: track,
            currentTime: currentTime,
            duration: duration,
            playbackRate: playbackRate,
            isPlaying: isPlaying
        )
    }

    private func configureRemoteCommands() {
        nowPlaying.configureCommands(
            play: { [weak self] in Task { @MainActor in self?.play() } },
            pause: { [weak self] in Task { @MainActor in self?.pause() } },
            skipForwardInterval: skipForwardSeconds,
            skipForward: { [weak self] in Task { @MainActor in self?.skipForward() } },
            skipBackwardInterval: skipBackSeconds,
            skipBackward: { [weak self] in Task { @MainActor in self?.skipBackward() } },
            seek: { [weak self] time in Task { @MainActor in self?.seek(to: time) } },
            supportedPlaybackRates: Self.supportedPlaybackRates,
            changePlaybackRate: { [weak self] rate in Task { @MainActor in self?.setPlaybackRate(rate) } }
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
