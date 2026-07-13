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

struct AudioSessionInterruptionController {
    enum Action: Equatable {
        case none
        case pause
        case resume
    }

    private var isInterruptionActive = false
    private var wasPlayingBeforeInterruption = false

    mutating func action(
        for type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions,
        isPlaying: Bool
    ) -> Action {
        switch type {
        case .began:
            if !isInterruptionActive {
                wasPlayingBeforeInterruption = isPlaying
            }
            isInterruptionActive = true
            return isPlaying ? .pause : .none

        case .ended:
            guard isInterruptionActive else { return .none }
            defer {
                isInterruptionActive = false
                wasPlayingBeforeInterruption = false
            }
            return wasPlayingBeforeInterruption && options.contains(.shouldResume)
                ? .resume
                : .none

        @unknown default:
            return .none
        }
    }
}

struct PlaybackLoadGeneration {
    private(set) var current: UInt64 = 0

    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    mutating func invalidate() {
        current &+= 1
    }

    func isCurrent(_ token: UInt64) -> Bool {
        token == current
    }
}

struct AudioPlayerLoadPreparation {
    let isNetworkAvailable: @MainActor () -> Bool
    let makeAudioMix: @MainActor (AVAsset) async -> AVAudioMix?
    let loadDuration: @MainActor (AVAsset) async throws -> CMTime
    /// Preparation-only hook. Must not seek the shared AVPlayer.
    let prepareSeek: @MainActor (AVAsset, CMTime) async -> Bool
}

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
    @Published private(set) var loadingPlaybackBookID: UUID?
    @Published var sleepTimerEndsAt: Date?
    @Published var playerErrorMessage: String?

    private let player = AVPlayer()
    private var timeObserverToken: Any?
    private var playbackEndedObserver: NSObjectProtocol?
    private var currentItemStatusObservation: NSKeyValueObservation?
    private var modelContext: ModelContext?
    private var resumeBacktrackSeconds: Double = ResumeBacktrackOption.oneMinute.rawValue
    private var skipBackSeconds: Double = SkipIntervalOption.thirty.rawValue
    private var skipForwardSeconds: Double = SkipIntervalOption.thirty.rawValue
    /// When true, the next Continue / library Resume / progress bookmark play may apply On Resume backtrack. Resets each app launch.
    private var resumeBacktrackAvailableThisLaunch = true
    private var sleepTimerTask: Task<Void, Never>?
    private var isLoadingItem = false
    private var loadGeneration = PlaybackLoadGeneration()
    private var seekGeneration: UInt64 = 0
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var backgroundObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionController = AudioSessionInterruptionController()
    private var loadPreparation: AudioPlayerLoadPreparation

    let persistence = PlaybackPersistence()
    private let nowPlaying = NowPlayingUpdater()
    private let sessionRecorder = ReadingSessionRecorder()
    let equalizer: AudioEqualizerService

    override convenience init() {
        self.init(loadPreparation: nil)
    }

    init(loadPreparation: AudioPlayerLoadPreparation?) {
        self.equalizer = AudioEqualizerService()
        self.loadPreparation = loadPreparation ?? AudioPlayerLoadPreparation(
            isNetworkAvailable: { false },
            makeAudioMix: { _ in nil },
            loadDuration: { _ in .zero },
            prepareSeek: { _, _ in false }
        )
        super.init()
        if loadPreparation == nil {
            self.loadPreparation = AudioPlayerLoadPreparation(
                isNetworkAvailable: { NetworkMonitor.shared.isConnected },
                makeAudioMix: { [weak self] asset in
                    guard let self else { return nil }
                    return await self.equalizer.makeAudioMix(for: asset)
                },
                loadDuration: { asset in
                    try await asset.load(.duration)
                },
                prepareSeek: { _, _ in true }
            )
        }
        player.automaticallyWaitsToMinimizeStalling = true
        addPeriodicTimeObserver()
        observeTrackEnd()
        observeTimeControlStatus()
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
                self.sessionRecorder.flush(context: self.modelContext)
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
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            Task { @MainActor in
                switch self.interruptionController.action(
                    for: type,
                    options: options,
                    isPlaying: self.isPlaying
                ) {
                case .pause:
                    self.pause()
                case .resume:
                    self.play()
                case .none:
                    break
                }
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        equalizer.configure(modelContext: modelContext)
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

    func seedUnitTestLoadingPlayback(bookID: UUID?) {
        loadingPlaybackBookID = bookID
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

    var isPreparingPlayback: Bool {
        loadingPlaybackBookID != nil
    }

    func isLoadingPlayback(for audiobook: Audiobook) -> Bool {
        loadingPlaybackBookID == audiobook.id
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
        invalidateCurrentLoad()
        pauseCurrentItemWithoutInvalidatingLoad()
    }

    private func pauseCurrentItemWithoutInvalidatingLoad() {
        player.pause()
        loadingPlaybackBookID = nil
        isPlaying = false
        updateProgressMarkerIfNeeded()
        persistPlayback(force: true)
        sessionRecorder.flush(context: modelContext)
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double, applyProgressPenalty: Bool = true) {
        if applyProgressPenalty {
            persistence.seekPenaltyRemaining = PlaybackPersistence.progressSeekPenalty
        }
        let boundedTime = max(0, min(seconds, duration))
        let target = CMTime(seconds: boundedTime, preferredTimescale: 600)
        seekGeneration &+= 1
        let seekToken = seekGeneration
        let loadToken = loadGeneration.current
        player.seek(to: target) { [weak self] finished in
            guard let self, finished else { return }
            Task { @MainActor in
                guard self.isCurrentLoad(loadToken), self.seekGeneration == seekToken else { return }
                self.currentTime = boundedTime
                self.persistPlayback(force: true)
                self.updateNowPlayingInfo()
            }
        }
    }

    func skipBackward() {
        let isSavingProgress = persistence.seekPenaltyRemaining == 0
        seek(to: currentTime - skipBackSeconds, applyProgressPenalty: !isSavingProgress)
    }

    func skipForward() {
        if currentTime + skipForwardSeconds >= duration - 1, canGoToNextTrack {
            nextTrack()
            return
        }
        let isSavingProgress = persistence.seekPenaltyRemaining == 0
        seek(to: currentTime + skipForwardSeconds, applyProgressPenalty: !isSavingProgress)
    }

    var canGoToNextTrack: Bool {
        guard let audiobook = currentAudiobook else { return false }
        return currentTrackIndex + 1 < audiobook.sortedTracks.count
    }

    var canGoToPreviousTrack: Bool {
        guard let audiobook = currentAudiobook, audiobook.sortedTracks.count > 1 else { return false }
        return currentTrackIndex > 0 || currentTime > 5
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

        let loadToken = beginLoad()
        persistence.seekPenaltyRemaining = PlaybackPersistence.progressSeekPenalty
        let showsStreamLoading = !audiobook.isDownloaded && autoplay
        loadingPlaybackBookID = showsStreamLoading ? audiobook.id : nil
        isLoadingItem = true
        activateAudioSession()

        do {
            let assetURL: URL
            if audiobook.isDownloaded {
                assetURL = try LibraryImportService.fileURL(for: track, in: audiobook)
            } else if let remoteURL = track.remoteURL {
                guard loadPreparation.isNetworkAvailable() else {
                    failCurrentLoad(
                        "You're offline. Download this book to listen without internet.",
                        loadToken: loadToken
                    )
                    return
                }
                assetURL = remoteURL
            } else {
                failCurrentLoad("No audio source available for this track.", loadToken: loadToken)
                return
            }
            let asset = AVURLAsset(url: assetURL)
            let item = AVPlayerItem(asset: asset)
            let initialDuration = track.duration > 0 ? track.duration : 1

            if let mix = await loadPreparation.makeAudioMix(asset) {
                guard isCurrentLoad(loadToken) else { return }
                item.audioMix = mix
            }

            let loadedDuration = try? await loadPreparation.loadDuration(asset)
            guard isCurrentLoad(loadToken) else { return }
            let committedDuration: Double
            if let loadedDuration, loadedDuration.seconds.isFinite, loadedDuration.seconds > 0 {
                committedDuration = loadedDuration.seconds
            } else {
                committedDuration = initialDuration
            }
            let startTime = max(0, min(time, committedDuration))
            let target = CMTime(seconds: startTime, preferredTimescale: 600)
            let shouldSeek = await loadPreparation.prepareSeek(asset, target)
            guard isCurrentLoad(loadToken) else { return }

            // Commit only after every suspending preparation step succeeds. Until this point,
            // current model state and shared AVPlayer remain owned by prior request.
            player.cancelPendingSeeks()
            player.pause()
            isPlaying = false
            player.replaceCurrentItem(with: item)
            if currentAudiobook !== audiobook {
                equalizer.bind(to: audiobook)
            }

            currentAudiobook = audiobook
            currentTrack = track
            currentTrackIndex = trackIndex
            currentTime = startTime
            playbackRate = audiobook.playbackRate
            duration = committedDuration
            audiobook.currentTrackIndex = trackIndex
            audiobook.currentTime = startTime
            audiobook.lastPlayedAt = .now
            audiobook.isFinished = false
            if let loadedDuration, loadedDuration.seconds.isFinite, loadedDuration.seconds > 0 {
                track.duration = loadedDuration.seconds
            }
            persistence.lastPersistedTime = startTime

            currentItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in
                    guard let self, failed, self.isCurrentLoad(loadToken) else { return }
                    self.isLoadingItem = false
                    self.clearLoadingPlayback(for: audiobook.id)
                    self.playerErrorMessage = "Unpaged could not open this audio stream."
                }
            }

            seekGeneration &+= 1
            let committedSeekToken = seekGeneration
            if shouldSeek {
                player.seek(to: target) { [weak self] finished in
                    guard let self, finished else { return }
                    Task { @MainActor in
                        guard self.isCurrentLoad(loadToken), self.seekGeneration == committedSeekToken else { return }
                        self.currentTime = startTime
                        self.persistPlayback(force: true)
                        self.updateNowPlayingInfo()
                    }
                }
            }

            isLoadingItem = false
            persistPlayback(force: true)

            if autoplay {
                play()
            } else {
                pauseCurrentItemWithoutInvalidatingLoad()
                clearLoadingPlayback(for: audiobook.id)
            }

            updateNowPlayingInfo()
        } catch {
            guard isCurrentLoad(loadToken) else { return }
            isLoadingItem = false
            clearLoadingPlayback(for: audiobook.id)
            playerErrorMessage = "Unpaged could not open this audio file."
        }
    }

    private func beginLoad() -> UInt64 {
        seekGeneration &+= 1
        player.cancelPendingSeeks()
        currentItemStatusObservation?.invalidate()
        currentItemStatusObservation = nil
        return loadGeneration.begin()
    }

    private func invalidateCurrentLoad() {
        loadGeneration.invalidate()
        seekGeneration &+= 1
        player.cancelPendingSeeks()
        currentItemStatusObservation?.invalidate()
        currentItemStatusObservation = nil
        isLoadingItem = false
        loadingPlaybackBookID = nil
    }

    private func isCurrentLoad(_ token: UInt64) -> Bool {
        loadGeneration.isCurrent(token)
    }

    private func failCurrentLoad(_ message: String, loadToken: UInt64) {
        guard isCurrentLoad(loadToken) else { return }
        isLoadingItem = false
        loadingPlaybackBookID = nil
        playerErrorMessage = message
    }

    private func clearLoadingPlayback(for bookID: UUID) {
        if loadingPlaybackBookID == bookID {
            loadingPlaybackBookID = nil
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
                if self.isPlaying, let bookID = self.currentAudiobook?.id {
                    self.clearLoadingPlayback(for: bookID)
                }
                if self.isPlaying, self.persistence.seekPenaltyRemaining > 0 {
                    self.persistence.seekPenaltyRemaining = max(0, self.persistence.seekPenaltyRemaining - 1)
                }
                if self.isPlaying, let book = self.currentAudiobook {
                    self.sessionRecorder.tick(audiobook: book, context: self.modelContext)
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

    private func observeTimeControlStatus() {
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                if player.timeControlStatus == .playing, let bookID = self.currentAudiobook?.id {
                    self.clearLoadingPlayback(for: bookID)
                }
                self.updateNowPlayingInfo()
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
        sessionRecorder.end(context: modelContext)
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
