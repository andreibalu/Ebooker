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
    /// Turns a stored, token-less Audiobookshelf track URL into a playable one. Resolved here, at
    /// play time, so no credential is ever persisted and a JWT refresh never breaks an older book.
    var resolveAudiobookshelfURL: @MainActor (URL) async throws -> URL = { url in url }
    /// Chapter markers embedded in a track's file (m4b/m4a chapter track, MP3 `CHAP`). Runs after
    /// the item commits, so it never delays playback.
    var loadChapterMarkers: @MainActor (AVAsset) async -> [ChapterMarker] = { _ in [] }
    /// Server-side chapters of an Audiobookshelf item (book-global times).
    var loadAudiobookshelfChapters: @MainActor (String) async throws -> [ABSChapter] = { _ in [] }
}

/// Target of a track load that has been requested but not committed yet. Chapter and track
/// navigation steps from here, so two quick taps on "next" advance twice instead of
/// re-requesting the same target from a position the player hasn't left yet.
struct PendingPlaybackTarget: Equatable {
    let bookID: UUID
    let trackIndex: Int
    let time: Double
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
    /// Chapters of the current book: embedded/server chapters when the files carry them,
    /// otherwise one per track.
    @Published private(set) var chapters: [PlaybackChapter] = []

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

    /// Receives Audiobookshelf progress at the recorder flush points. Fire-and-forget by contract.
    var audiobookshelfProgressSink: @MainActor (ABSProgressSnapshot) -> Void = { ABSProgressReporter.report($0) }
    /// One silent re-resolve per load when an Audiobookshelf stream fails (e.g. its token aged out
    /// mid-listen); a second failure surfaces the error.
    private var audiobookshelfRecoveryLoadToken: UInt64?

    /// Requested-but-uncommitted track load; see `PendingPlaybackTarget`.
    private(set) var pendingPlaybackTarget: PendingPlaybackTarget?
    /// Target of an in-flight seek. While set, periodic time callbacks still report the pre-seek
    /// position (or 0 for a fresh item), so they must not overwrite `currentTime` — doing so
    /// flickered the chapter highlight, made a second chapter tap step from the old chapter, and
    /// could persist (and recover a failed stream at) position 0.
    private var pendingSeek: (time: Double, issuedAt: Date)?
    /// Embedded chapter markers per track file, cached for the session.
    private var chapterMarkersByTrackKey: [String: [ChapterMarker]] = [:]
    /// Audiobookshelf server chapters per item, cached for the session.
    private var audiobookshelfChaptersByItemID: [String: [ABSChapter]] = [:]

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
                prepareSeek: { _, _ in true },
                resolveAudiobookshelfURL: { url in
                    try await ABSAccount.shared.client.playbackURL(forStoredURL: url)
                },
                loadChapterMarkers: { asset in
                    await EmbeddedChapterReader.markers(from: asset)
                },
                loadAudiobookshelfChapters: { itemID in
                    try await ABSAccount.shared.client.item(id: itemID).media.chapters ?? []
                }
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
                self.reportAudiobookshelfProgress()
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
        rebuildChapters()
    }

    /// Seeds embedded chapter markers for a track, as if they had been read from its file.
    func seedUnitTestChapterMarkers(_ markers: [ChapterMarker], for track: AudioTrack) {
        chapterMarkersByTrackKey[Self.chapterCacheKey(for: track)] = markers
        rebuildChapters()
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
        // Only an uncommitted load is abandoned. Invalidating a committed item also cancelled its
        // in-flight seek, so pausing while a stream was still buffering a chapter jump (or the
        // resume position) left the item at 0 and the next play started from the wrong place.
        if isLoadingItem || pendingPlaybackTarget != nil {
            invalidateCurrentLoad()
        }
        pauseCurrentItemWithoutInvalidatingLoad()
    }

    private func pauseCurrentItemWithoutInvalidatingLoad() {
        player.pause()
        loadingPlaybackBookID = nil
        isPlaying = false
        updateProgressMarkerIfNeeded()
        persistPlayback(force: true)
        sessionRecorder.flush(context: modelContext)
        reportAudiobookshelfProgress()
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
        // Reflect the target right away: the chapter highlight, the scrubber and any follow-up
        // navigation (a second "next chapter" tap) must step from where the user asked to be.
        currentTime = boundedTime
        pendingSeek = (boundedTime, Date())
        player.seek(to: target) { [weak self] finished in
            guard let self else { return }
            Task { @MainActor in
                guard self.isCurrentLoad(loadToken), self.seekGeneration == seekToken else { return }
                self.pendingSeek = nil
                guard finished else { return }
                self.currentTime = boundedTime
                self.persistPlayback(force: true)
                self.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - Chapters

    /// Index into `chapters` of the chapter at the current (or requested) position.
    var currentChapterIndex: Int? {
        let position = navigationPosition
        return PlaybackChapterList.chapterIndex(in: chapters, trackIndex: position.trackIndex, time: position.time)
    }

    var currentChapter: PlaybackChapter? {
        currentChapterIndex.flatMap { chapters.indices.contains($0) ? chapters[$0] : nil }
    }

    var canGoToNextChapter: Bool {
        guard let index = currentChapterIndex else { return false }
        return index + 1 < chapters.count
    }

    var canGoToPreviousChapter: Bool {
        guard chapters.count > 1, let index = currentChapterIndex else { return false }
        return index > 0 || navigationPosition.time - chapters[index].start > Self.chapterRestartThreshold
    }

    func nextChapter() {
        guard let index = currentChapterIndex, chapters.indices.contains(index + 1) else { return }
        jump(to: chapters[index + 1])
    }

    /// Restarts the current chapter when more than a few seconds in, otherwise goes back one.
    func previousChapter() {
        guard let index = currentChapterIndex, chapters.indices.contains(index) else { return }
        let current = chapters[index]
        let position = navigationPosition
        let intoChapter = position.trackIndex == current.trackIndex
            ? position.time - current.start
            : Self.chapterRestartThreshold + 1
        if intoChapter > Self.chapterRestartThreshold || index == 0 {
            jump(to: current)
        } else {
            jump(to: chapters[index - 1])
        }
    }

    /// Chapter-list tap: jump to the chapter and play.
    func playChapter(_ chapter: PlaybackChapter) {
        jump(to: chapter, startPlaying: true)
    }

    private static let chapterRestartThreshold: Double = 5

    private func jump(to chapter: PlaybackChapter, startPlaying: Bool = false) {
        navigate(toTrack: chapter.trackIndex, time: chapter.start, startPlaying: startPlaying)
    }

    /// Where navigation steps from: the pending load target for this book if one is in flight,
    /// otherwise the committed position.
    private var navigationPosition: (trackIndex: Int, time: Double) {
        if let target = pendingPlaybackTarget, target.bookID == currentAudiobook?.id {
            return (target.trackIndex, target.time)
        }
        return (currentTrackIndex, currentTime)
    }

    /// Seeks inside the committed item when the target is in it; otherwise loads the target track.
    /// Track loads always autoplay (as track navigation always has); in-item seeks keep the
    /// play/pause state unless `startPlaying`.
    private func navigate(toTrack trackIndex: Int, time: Double, startPlaying: Bool = false) {
        guard let audiobook = currentAudiobook,
              audiobook.sortedTracks.indices.contains(trackIndex) else { return }
        if pendingPlaybackTarget == nil, trackIndex == currentTrackIndex, player.currentItem != nil {
            seek(to: time)
            if startPlaying, !isPlaying { play() }
            return
        }
        // Record the target synchronously so a second tap before the load task runs steps from it.
        let target = PendingPlaybackTarget(bookID: audiobook.id, trackIndex: trackIndex, time: time)
        pendingPlaybackTarget = target
        Task { [weak self] in
            // Pause or a newer chapter request can cancel this before its task starts.
            guard let self, self.pendingPlaybackTarget == target else { return }
            await self.load(audiobook: audiobook, trackIndex: trackIndex, time: time, autoplay: true)
        }
    }

    private static func chapterCacheKey(for track: AudioTrack) -> String {
        "\(track.id.uuidString)|\(track.storedFileName)|\(track.remoteURLString ?? "")"
    }

    /// Recomputes `chapters` for the current book from the server chapters (Audiobookshelf), the
    /// embedded markers read so far, or one chapter per track.
    private func rebuildChapters() {
        guard let audiobook = currentAudiobook else {
            if !chapters.isEmpty { chapters = [] }
            return
        }
        let tracks = audiobook.sortedTracks
        var rebuilt: [PlaybackChapter] = []
        if let itemID = audiobook.absItemID, let serverChapters = audiobookshelfChaptersByItemID[itemID] {
            rebuilt = AudiobookshelfLibraryService.playbackChapters(
                from: serverChapters,
                trackDurations: tracks.map(\.duration)
            )
        }
        if rebuilt.isEmpty {
            var markers: [Int: [ChapterMarker]] = [:]
            for (index, track) in tracks.enumerated() {
                if let found = chapterMarkersByTrackKey[Self.chapterCacheKey(for: track)] {
                    markers[index] = found
                }
            }
            rebuilt = PlaybackChapterList.build(
                trackTitles: tracks.map(\.displayTitle),
                trackDurations: tracks.map(\.duration),
                markersByTrack: markers
            )
        }
        if rebuilt != chapters { chapters = rebuilt }
    }

    /// Reads chapters for the committed item off the playback path, then rebuilds the list if the
    /// same book is still current.
    private func loadChapters(for audiobook: Audiobook, track: AudioTrack, asset: AVAsset) {
        let bookID = audiobook.id
        if let itemID = audiobook.absItemID, audiobookshelfChaptersByItemID[itemID] == nil {
            Task { [weak self] in
                guard let self,
                      let serverChapters = try? await self.loadPreparation.loadAudiobookshelfChapters(itemID)
                else { return }
                self.audiobookshelfChaptersByItemID[itemID] = serverChapters
                if self.currentAudiobook?.id == bookID { self.rebuildChapters() }
            }
        }
        // LibriVox sections are one file per chapter and never carry chapter atoms; skip the probe
        // so streaming a free book doesn't spend extra requests on it.
        guard !audiobook.isFreeBook else { return }
        let key = Self.chapterCacheKey(for: track)
        guard chapterMarkersByTrackKey[key] == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            let markers = await self.loadPreparation.loadChapterMarkers(asset)
            // A stream that failed to load reads as "no chapters"; let the next load retry it.
            guard !markers.isEmpty || audiobook.isDownloaded else { return }
            self.chapterMarkersByTrackKey[key] = markers
            if self.currentAudiobook?.id == bookID { self.rebuildChapters() }
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
        return navigationPosition.trackIndex + 1 < audiobook.sortedTracks.count
    }

    var canGoToPreviousTrack: Bool {
        guard let audiobook = currentAudiobook, audiobook.sortedTracks.count > 1 else { return false }
        let position = navigationPosition
        return position.trackIndex > 0 || position.time > 5
    }

    func nextTrack() {
        guard currentAudiobook != nil, canGoToNextTrack else {
            markCurrentBookFinished()
            return
        }
        navigate(toTrack: navigationPosition.trackIndex + 1, time: 0)
    }

    func previousTrack() {
        guard currentAudiobook != nil else { return }
        let position = navigationPosition
        if position.time > 5 {
            navigate(toTrack: position.trackIndex, time: 0)
            return
        }
        navigate(toTrack: max(position.trackIndex - 1, 0), time: 0)
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
        guard var seconds else {
            sleepTimerEndsAt = nil
            return
        }
        #if DEBUG
        // E2E runs compress every sleep-timer choice so expiry is observable in seconds.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-e2e-fixture"),
           let index = arguments.firstIndex(of: "-e2e-sleep-timer-seconds"),
           arguments.indices.contains(index + 1),
           let override = Double(arguments[index + 1]) {
            seconds = override
        }
        #endif
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

    private func load(
        audiobook: Audiobook,
        trackIndex: Int,
        time: Double,
        autoplay: Bool,
        isAudiobookshelfRecovery: Bool = false
    ) async {
        guard audiobook.sortedTracks.indices.contains(trackIndex) else { return }
        guard let track = audiobook.sortedTracks[safe: trackIndex] else { return }

        let loadToken = beginLoad()
        pendingPlaybackTarget = PendingPlaybackTarget(bookID: audiobook.id, trackIndex: trackIndex, time: time)
        audiobookshelfRecoveryLoadToken = isAudiobookshelfRecovery ? loadToken : nil
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
                        audiobook.isAudiobookshelfBook
                            ? "You're offline. Connect to the internet to stream from your Audiobookshelf server."
                            : "You're offline. Download this book to listen without internet.",
                        loadToken: loadToken
                    )
                    return
                }
                if audiobook.isAudiobookshelfBook {
                    do {
                        assetURL = try await loadPreparation.resolveAudiobookshelfURL(remoteURL)
                    } catch {
                        failCurrentLoad(Self.audiobookshelfPlaybackMessage(for: error), loadToken: loadToken)
                        return
                    }
                    guard isCurrentLoad(loadToken) else { return }
                } else {
                    assetURL = remoteURL
                }
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
            player.currentItem?.cancelPendingSeeks()
            // Track or book change is a flush point: hand the outgoing position to the server.
            reportAudiobookshelfProgress()
            player.pause()
            isPlaying = false
            player.replaceCurrentItem(with: item)
            if currentAudiobook !== audiobook {
                equalizer.bind(to: audiobook)
            }

            pendingPlaybackTarget = nil
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
            rebuildChapters()
            loadChapters(for: audiobook, track: track, asset: asset)

            let audiobookID = audiobook.id
            currentItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in
                    guard let self, failed, self.isCurrentLoad(loadToken) else { return }
                    let failedBook = self.currentAudiobook?.id == audiobookID ? self.currentAudiobook : nil
                    if let failedBook, failedBook.isAudiobookshelfBook, self.audiobookshelfRecoveryLoadToken == nil {
                        // Re-resolve once with a fresh token from where the listener was.
                        let resumeAt = self.currentTime
                        let index = self.currentTrackIndex
                        let resumePlaying = self.isPlaying || self.loadingPlaybackBookID == audiobookID
                        Task { @MainActor in
                            await self.load(audiobook: failedBook, trackIndex: index, time: resumeAt,
                                            autoplay: resumePlaying, isAudiobookshelfRecovery: true)
                        }
                        return
                    }
                    self.isLoadingItem = false
                    self.clearLoadingPlayback(for: audiobookID)
                    self.playerErrorMessage = failedBook?.isAudiobookshelfBook == true
                        ? "Unpaged couldn't stream this book from your Audiobookshelf server."
                        : "Unpaged could not open this audio stream."
                }
            }

            seekGeneration &+= 1
            let committedSeekToken = seekGeneration
            if shouldSeek {
                pendingSeek = (startTime, Date())
                player.seek(to: target) { [weak self] finished in
                    guard let self else { return }
                    Task { @MainActor in
                        guard self.isCurrentLoad(loadToken), self.seekGeneration == committedSeekToken else { return }
                        self.pendingSeek = nil
                        guard finished else { return }
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
            pendingPlaybackTarget = nil
            clearLoadingPlayback(for: audiobook.id)
            playerErrorMessage = "Unpaged could not open this audio file."
        }
    }

    private func beginLoad() -> UInt64 {
        seekGeneration &+= 1
        pendingSeek = nil
        player.currentItem?.cancelPendingSeeks()
        currentItemStatusObservation?.invalidate()
        currentItemStatusObservation = nil
        return loadGeneration.begin()
    }

    private func invalidateCurrentLoad() {
        loadGeneration.invalidate()
        seekGeneration &+= 1
        pendingSeek = nil
        pendingPlaybackTarget = nil
        player.currentItem?.cancelPendingSeeks()
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
        pendingPlaybackTarget = nil
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
                self.applyObservedTime(time.seconds)

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

    /// Applies a periodic time callback. While a seek is in flight AVPlayer still reports the
    /// pre-seek position, so the reading is ignored until it reaches the target or the seek
    /// completes (a stale seek is given up on after a while so time can never freeze).
    func applyObservedTime(_ seconds: Double, now: Date = Date()) {
        let observed = seconds.isFinite ? max(seconds, 0) : 0
        if let seek = pendingSeek {
            let landed = abs(observed - seek.time) < 1.5
            let expired = now.timeIntervalSince(seek.issuedAt) > 15
            guard landed || expired else { return }
            pendingSeek = nil
        }
        currentTime = observed
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
        reportAudiobookshelfProgress(isFinished: true)
        updateNowPlayingInfo()
    }

    // MARK: - Audiobookshelf progress

    /// Pushes the current position of an Audiobookshelf book to its server. Called at the same
    /// flush points as the reading-session recorder: pause, track/book change, background, finish.
    private func reportAudiobookshelfProgress(isFinished: Bool = false) {
        guard let audiobook = currentAudiobook, audiobook.isAudiobookshelfBook,
              let snapshot = AudiobookshelfLibraryService.progressSnapshot(
                  for: audiobook,
                  trackIndex: currentTrackIndex,
                  timeInTrack: currentTime,
                  isFinished: isFinished
              ) else { return }
        audiobookshelfProgressSink(snapshot)
    }

    static func audiobookshelfPlaybackMessage(for error: Error) -> String {
        switch error as? AudiobookshelfError {
        case .notConnected?:
            return "Connect your Audiobookshelf server in Settings to play this book."
        case .invalidMediaURL?:
            return "This book is from a different Audiobookshelf server. Connect to that server to play it."
        case .badCredentials?, .expiredToken?, .inactiveAPIKey?:
            return "Your Audiobookshelf sign-in has expired. Reconnect in Settings to keep listening."
        case .offline?:
            return "You're offline. Connect to the internet to stream from your Audiobookshelf server."
        default:
            return "Unpaged can't reach your Audiobookshelf server right now."
        }
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
