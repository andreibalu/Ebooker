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
    /// Whether the load starts playing once it commits. Skip back and undo on a paused book load
    /// without autoplay, so they stay paused.
    var autoplay: Bool = true
}

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    /// Shared with CarPlay cycle controls and Now Playing remote rate command.
    static let supportedPlaybackRates: [Double] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0]
    /// Presets shown in the phone player's speed menu.
    static let playerPresetPlaybackRates: [Double] = [0.8, 1.0, 1.1, 1.2, 1.25, 1.3, 1.5, 1.75, 2.0, 2.5, 3.0]
    static let minPlaybackRate: Double = 0.5
    static let maxPlaybackRate: Double = 3.0
    static let playbackRateStep: Double = 0.05

    static func normalizedPlaybackRate(_ rate: Double) -> Double {
        let safe = rate.isFinite ? rate : 1.0
        let rounded = (safe * 100).rounded() / 100
        return min(max(rounded, minPlaybackRate), maxPlaybackRate)
    }
    @Published private(set) var currentAudiobook: Audiobook?
    @Published private(set) var currentTrack: AudioTrack?
    @Published private(set) var currentTrackIndex = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 1
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double = 1
    @Published private(set) var loadingPlaybackBookID: UUID?
    @Published var sleepTimerEndsAt: Date?
    @Published private(set) var sleepAtChapterEnd = false
    private var sleepChapterEnd: Double?
    /// The item a chapter sleep timer stopped at its end; Play continues with the next file.
    private weak var chapterSleepEndedItem: AVPlayerItem?
    @Published var playerErrorMessage: String?
    /// Chapters of the current book: embedded/server chapters when the files carry them,
    /// otherwise one per track.
    @Published private(set) var chapters: [PlaybackChapter] = []
    /// The point the last scrub or chapter jump left, while "Back to 14:22" is on offer.
    @Published private(set) var jumpUndo: JumpUndo?
    private var jumpUndoExpiryTask: Task<Void, Never>?

    /// When the current break in listening began; see `docs/ios/playback.md`. Set by `pause()` and
    /// by a load that commits without autoplay; cleared by autoplaying loads and any user
    /// positioning. `play()` consumes it. Not `lastPlayedAt`, which saves also stamp.
    private var smartRewindAnchor: Date?
    /// In-memory last moment each book was audible, for the break measured by a fresh load.
    private var lastAudibleAt: [UUID: Date] = [:]

    private let player = AVPlayer()
    private var timeObserverToken: Any?
    private var playbackEndedObserver: NSObjectProtocol?
    private var currentItemStatusObservation: NSKeyValueObservation?
    private var modelContext: ModelContext?
    private var resumeBacktrackSeconds: Double = ResumeBacktrackOption.oneMinute.rawValue
    private var skipBackSeconds: Double = SkipIntervalOption.thirty.rawValue
    private var skipForwardSeconds: Double = SkipIntervalOption.thirty.rawValue
    private var sleepTimerTask: Task<Void, Never>?
    private var isLoadingItem = false
    private var loadGeneration = PlaybackLoadGeneration()
    private var absResumeGeneration: UInt64 = 0
    @Published private var absResumeWaiters = 0
    /// Set on pause. Resuming an ABS book after a long pause — or with no pause this session, i.e. a
    /// book restored after relaunch — checks the server for progress made on another device; a quick
    /// pause/play skips the round trip. Fresh loads reconcile in `startPlayback`.
    private var pausedAt: Date?
    private static let absReconcileAfterPause: TimeInterval = 5 * 60
    private var seekGeneration: UInt64 = 0
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var backgroundObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionController = AudioSessionInterruptionController()
    private var loadPreparation: AudioPlayerLoadPreparation

    /// Receives Audiobookshelf progress at the recorder flush points. Fire-and-forget by contract.
    var audiobookshelfProgressSink: @MainActor (ABSProgressSnapshot) -> Void = { ABSProgressReporter.report($0) }
    /// Called when a book plays to its end. The default feeds the rating prompt's positive-moment history.
    var bookFinishedSink: @MainActor () -> Void = { RatingPromptStore.standard.recordFinishedBook() }
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

        // AVPlayer pauses itself when headphones are unplugged, which saves nothing and sets no
        // break anchor. Pausing here makes it a normal pause.
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                self.pauseAfterRouteLoss()
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

    func seedUnitTestPendingPlaybackTarget(_ target: PendingPlaybackTarget?) {
        pendingPlaybackTarget = target
    }

    /// Starts a break at `date`, as `pause()` would have; nil means no break is recorded.
    func seedUnitTestSmartRewindAnchor(_ date: Date?) {
        smartRewindAnchor = date
    }

    var hasSmartRewindAnchorForTesting: Bool {
        smartRewindAnchor != nil
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

    /// True while a play request waits on the Audiobookshelf server for newer progress, before
    /// `isPlaying` or `loadingPlaybackBookID` is set. A count, because a superseded request still unwinds.
    var isAwaitingServerResume: Bool {
        absResumeWaiters > 0
    }

    func isLoadingPlayback(for audiobook: Audiobook) -> Bool {
        loadingPlaybackBookID == audiobook.id
    }

    /// `adoptedServerProgress` is nil when the Audiobookshelf position still needs reconciling.
    /// `elapsed` is the break already measured by a caller that awaited first (nil: measure now).
    func startPlayback(
        for audiobook: Audiobook,
        autoplay: Bool = true,
        adoptedServerProgress: Bool? = nil,
        elapsed: TimeInterval? = nil
    ) async {
        clearJumpUndo()
        // Measured before the reconcile await, so the server round trip isn't counted as a break.
        let elapsed = elapsed ?? measuredFreshLoadElapsed(for: audiobook)
        var adopted = adoptedServerProgress ?? false
        if adoptedServerProgress == nil {
            guard let reconciled = await reconcileAudiobookshelfBeforeResume(audiobook) else { return }
            adopted = reconciled
        }
        let trackIndex = audiobook.isFinished ? 0 : audiobook.currentTrackIndex
        let baseTime = audiobook.isFinished ? 0 : audiobook.currentTime
        let rewind = adopted || audiobook.isFinished
            ? 0
            : SmartRewindPolicy.rewindSeconds(elapsed: elapsed, setting: resumeBacktrackSeconds)
        let target = RewindPosition.target(
            trackIndex: trackIndex,
            time: baseTime,
            seconds: rewind,
            trackDurations: audiobook.sortedTracks.map(\.duration)
        )
        await load(audiobook: audiobook, trackIndex: target.trackIndex, time: target.time, autoplay: autoplay)
    }

    /// Starts like tapping “Your progress” on the book detail: uses the saved progress marker when set (with Smart Rewind), otherwise last playback position.
    /// Audiobookshelf books reconcile with the server first; an adopted server position wins,
    /// otherwise the saved marker is honored like any other book.
    func startPlaybackFromSavedProgress(for audiobook: Audiobook, autoplay: Bool = true) async {
        let elapsed = measuredFreshLoadElapsed(for: audiobook)
        guard let adopted = await reconcileAudiobookshelfBeforeResume(audiobook) else { return }
        if adopted {
            await startPlayback(for: audiobook, autoplay: autoplay, adoptedServerProgress: true, elapsed: elapsed)
            return
        }
        switch AudiobookSavedProgressResume.startChoice(for: audiobook) {
        case .useProgressBookmark(let idx, let t):
            await playProgressBookmark(at: idx, in: audiobook, time: t, autoplay: autoplay, elapsed: elapsed)
        case .useStandardStartPlayback:
            await startPlayback(for: audiobook, autoplay: autoplay, adoptedServerProgress: false, elapsed: elapsed)
        }
    }

    /// Whether a newer server position was adopted, or nil when a later start superseded this one.
    private func reconcileAudiobookshelfBeforeResume(_ audiobook: Audiobook) async -> Bool? {
        absResumeGeneration &+= 1
        let resumeToken = absResumeGeneration
        absResumeWaiters += 1
        defer { absResumeWaiters -= 1 }
        let adopted = await AudiobookshelfLibraryService.reconcileBeforeResume(audiobook, context: modelContext)
        return resumeToken == absResumeGeneration ? adopted : nil
    }

    func restart(_ audiobook: Audiobook) async {
        clearJumpUndo()
        audiobook.currentTrackIndex = 0
        audiobook.currentTime = 0
        audiobook.isFinished = false
        try? modelContext?.save()
        await load(audiobook: audiobook, trackIndex: 0, time: 0, autoplay: true)
    }

    func playTrack(at index: Int, in audiobook: Audiobook, time: Double = 0, autoplay: Bool = true) async {
        clearJumpUndo()
        await load(audiobook: audiobook, trackIndex: index, time: time, autoplay: autoplay)
    }

    /// Like `playTrack`, but applies Smart Rewind like `startPlayback` (Your progress row).
    func playProgressBookmark(
        at index: Int,
        in audiobook: Audiobook,
        time: Double,
        autoplay: Bool = true,
        elapsed: TimeInterval? = nil
    ) async {
        clearJumpUndo()
        let elapsed = elapsed ?? measuredFreshLoadElapsed(for: audiobook)
        let rewind = audiobook.isFinished
            ? 0
            : SmartRewindPolicy.rewindSeconds(elapsed: elapsed, setting: resumeBacktrackSeconds)
        let target = RewindPosition.target(
            trackIndex: index,
            time: time,
            seconds: rewind,
            trackDurations: audiobook.sortedTracks.map(\.duration)
        )
        await load(audiobook: audiobook, trackIndex: target.trackIndex, time: target.time, autoplay: autoplay)
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play(reconcileABS: Bool = true) {
        // Read before the ABS reconcile below, so the server round trip isn't counted as a break.
        let elapsed = measuredAnchorElapsed()
        if reconcileABS, !isPlaying, let book = currentAudiobook, book.isAudiobookshelfBook,
           pausedAt.map({ Date.now.timeIntervalSince($0) >= Self.absReconcileAfterPause }) ?? true,
           NetworkMonitor.shared.isConnected {
            absResumeGeneration &+= 1
            let resumeToken = absResumeGeneration
            absResumeWaiters += 1
            Task {
                // Held through the follow-up load, so no gap opens before `loadingPlaybackBookID` is set.
                defer { absResumeWaiters -= 1 }
                let adopted = await AudiobookshelfLibraryService.reconcileBeforeResume(book, context: modelContext)
                guard resumeToken == absResumeGeneration, currentAudiobook === book else { return }
                if adopted {
                    // The server position is the user's place now; no rewind on top of it.
                    smartRewindAnchor = nil
                    clearJumpUndo()
                    currentTrackIndex = book.currentTrackIndex
                    currentTime = book.currentTime
                    await load(audiobook: book, trackIndex: book.currentTrackIndex, time: book.currentTime, autoplay: true)
                } else {
                    resumePlayback(elapsedSinceBreak: elapsed)
                }
            }
            return
        }
        resumePlayback(elapsedSinceBreak: elapsed)
    }

    /// The tail of `play()` once any server reconcile is settled. `elapsedSinceBreak` is nil when no
    /// break was recorded; a user positioning since (anchor cleared) cancels the rewind too.
    private func resumePlayback(elapsedSinceBreak: TimeInterval?) {
        // A chapter sleep timer that expired at the end of a file leaves the ended item loaded;
        // playing it again does nothing, so continue with the next file instead. It starts the
        // file at 0 and drops the anchor, so a rewind can't cross back into the chapter that ended.
        if let ended = chapterSleepEndedItem, ended === player.currentItem,
           pendingSeek == nil, pendingPlaybackTarget == nil, !isLoadingItem, canGoToNextTrack {
            chapterSleepEndedItem = nil
            smartRewindAnchor = nil
            navigate(toTrack: navigationPosition.trackIndex + 1, time: 0)
            return
        }
        chapterSleepEndedItem = nil
        let hadBreak = smartRewindAnchor != nil
        smartRewindAnchor = nil
        if hadBreak, !isPlaying, let elapsedSinceBreak, applySmartRewind(elapsed: elapsedSinceBreak) {
            return
        }
        player.play()
        player.rate = Float(playbackRate)
        isPlaying = true
        updateNowPlayingInfo()
    }

    /// Steps the position back by the tier for `elapsed`. Returns true when it started a track load
    /// that autoplays (so the caller must not also start the current item).
    private func applySmartRewind(elapsed: TimeInterval) -> Bool {
        guard let book = currentAudiobook, player.currentItem != nil, pendingPlaybackTarget == nil else { return false }
        let rewind = SmartRewindPolicy.rewindSeconds(elapsed: elapsed, setting: resumeBacktrackSeconds)
        guard rewind > 0 else { return false }
        let target = RewindPosition.target(
            trackIndex: currentTrackIndex,
            time: currentTime,
            seconds: rewind,
            trackDurations: book.sortedTracks.map(\.duration)
        )
        let isSavingProgress = persistence.seekPenaltyRemaining == 0
        if target.trackIndex != currentTrackIndex {
            navigate(
                toTrack: target.trackIndex,
                time: target.time,
                autoplay: true,
                seekPenaltyOverride: Self.rewindPenalty(isSavingProgress: isSavingProgress)
            )
            return true
        }
        guard target.time < currentTime else { return false }
        seek(to: target.time, applyProgressPenalty: !isSavingProgress)
        return false
    }

    /// A rewind keeps a running seek penalty and starts none, like `skipBackward()`: while progress
    /// is saving it stays saving, and the high-water marker never moves backward either way.
    private static func rewindPenalty(isSavingProgress: Bool) -> Double {
        isSavingProgress ? 0 : PlaybackPersistence.progressSeekPenalty
    }

    func pause() {
        pauseInternal(wasActive: isPlaying || isLoadingItem || pendingPlaybackTarget != nil)
    }

    /// `wasActive` is false for a duplicate pause command, which must not move the break's start later.
    private func pauseInternal(wasActive: Bool) {
        absResumeGeneration &+= 1
        pausedAt = .now
        if wasActive {
            smartRewindAnchor = .now
            if let id = currentAudiobook?.id { lastAudibleAt[id] = .now }
        }
        // Only an uncommitted load is abandoned. Invalidating a committed item also cancelled its
        // in-flight seek, so pausing while a stream was still buffering a chapter jump (or the
        // resume position) left the item at 0 and the next play started from the wrong place.
        if isLoadingItem || pendingPlaybackTarget != nil {
            invalidateCurrentLoad()
        }
        pauseCurrentItemWithoutInvalidatingLoad()
    }

    /// Headphones or another output went away. AVPlayer has usually paused already, so `isPlaying`
    /// may be false; the periodic observer's last audible stamp says whether this was playback.
    private func pauseAfterRouteLoss() {
        guard let id = currentAudiobook?.id else { return }
        let recentlyAudible = lastAudibleAt[id].map { Date.now.timeIntervalSince($0) < 3 } ?? false
        let wasActive = isPlaying || isLoadingItem || pendingPlaybackTarget != nil || recentlyAudible
        guard wasActive else { return }
        pauseInternal(wasActive: true)
    }

    /// Stops and forgets `audiobook` if it is loaded, before its row is deleted. Otherwise the
    /// mini player, Now Playing and the time observer keep reading a deleted SwiftData model.
    func unloadIfCurrent(_ audiobook: Audiobook) {
        // `currentAudiobook` still names the previous book while another one prepares, and
        // `loadingPlaybackBookID` is set only for autoplaying streams, so check the pending target too.
        guard currentAudiobook?.id == audiobook.id
            || loadingPlaybackBookID == audiobook.id
            || pendingPlaybackTarget?.bookID == audiobook.id else { return }
        // Pausing first saves the position, flushes the reading session and reports ABS progress.
        pause()
        invalidateCurrentLoad()
        clearJumpUndo()
        smartRewindAnchor = nil
        lastAudibleAt[audiobook.id] = nil
        setSleepTimer(seconds: nil)
        player.replaceCurrentItem(with: nil)
        currentAudiobook = nil
        currentTrack = nil
        currentTrackIndex = 0
        currentTime = 0
        duration = 1
        chapters = []
        nowPlaying.clear()
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
        chapterSleepEndedItem = nil
        // The user picked the spot, so the next play() doesn't rewind from it.
        smartRewindAnchor = nil
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
        refreshChapterSleepBoundary()
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

    /// True when the current audio file is subdivided into chapters (single-file M4B or
    /// Audiobookshelf chapters), so chapter-scoped scrubbing covers a narrower range than the file.
    var hasSubTrackChapters: Bool {
        guard chapters.count > 1 else { return false }
        let trackIdx = navigationPosition.trackIndex
        if chapters.filter({ $0.trackIndex == trackIdx }).count > 1 { return true }
        guard let chapter = currentChapter, chapter.trackIndex == trackIdx else { return false }
        return chapter.start > 0.5 || (duration > 1 && chapter.duration < duration - 0.5)
    }

    /// Track-local time range for the current chapter when `hasSubTrackChapters` is true.
    var currentTrackChapterRange: ClosedRange<Double>? {
        guard hasSubTrackChapters,
              let chapter = currentChapter,
              chapter.trackIndex == navigationPosition.trackIndex else { return nil }
        let trackEnd = max(duration, 1)
        let start = min(max(chapter.start, 0), max(trackEnd - 1, 0))
        let rawEnd = chapter.duration > 0 ? chapter.start + chapter.duration : trackEnd
        let end = min(max(rawEnd, start + 1), trackEnd)
        guard end > start else { return nil }
        return start...end
    }

    /// Remaining audio seconds across the loaded book from the live playhead (unadjusted for rate).
    var currentBookRemainingDuration: Double {
        guard let book = currentAudiobook else { return 0 }
        let tracks = book.sortedTracks
        let pos = navigationPosition
        let remainingInTrack = max(duration - pos.time, 0)
        let laterTracks = tracks.enumerated()
            .filter { $0.offset > pos.trackIndex }
            .reduce(0.0) { $0 + $1.element.duration }
        return max(remainingInTrack + laterTracks, 0)
    }

    /// Whole-book position for the player's progress line, from the same positional sums as
    /// `currentBookRemainingDuration` (stored durations of the other tracks, the live `duration` for
    /// the current one), never `Audiobook.progress`. `fraction` is 0...1 and unadjusted; the view
    /// floors it and holds it under 100% until the book is finished. `remainingSeconds` is unadjusted
    /// for playback speed. Nil when the total is 0. `currentTrackTimeOverride` follows a scrub.
    func bookPositionSummary(currentTrackTimeOverride: Double? = nil) -> (fraction: Double, remainingSeconds: Double)? {
        guard let book = currentAudiobook else { return nil }
        let durations = book.sortedTracks.map(\.duration)
        let position = navigationPosition
        guard durations.indices.contains(position.trackIndex) else { return nil }
        // `duration` is the committed track's live length; a pending target uses its stored one.
        let trackLength = position.trackIndex == currentTrackIndex ? duration : durations[position.trackIndex]
        let before = durations.prefix(position.trackIndex).reduce(0, +)
        let after = durations.suffix(from: position.trackIndex + 1).reduce(0, +)
        let total = before + trackLength + after
        guard total.isFinite, total > 0 else { return nil }
        let time = min(max(currentTrackTimeOverride ?? position.time, 0), max(trackLength, 0))
        let listened = before + time
        return (min(max(listened / total, 0), 1), max(total - listened, 0))
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
    /// Track loads autoplay unless `autoplay` says otherwise (skip back and undo pass the current
    /// play intent); in-item seeks keep the play/pause state unless `startPlaying`.
    /// `seekPenaltyOverride` replaces the usual seek penalty, applied after a load commits.
    private func navigate(
        toTrack trackIndex: Int,
        time: Double,
        startPlaying: Bool = false,
        autoplay: Bool = true,
        seekPenaltyOverride: Double? = nil
    ) {
        guard let audiobook = currentAudiobook,
              audiobook.sortedTracks.indices.contains(trackIndex) else { return }
        smartRewindAnchor = nil
        if pendingPlaybackTarget == nil, trackIndex == currentTrackIndex, player.currentItem != nil {
            seek(to: time, applyProgressPenalty: seekPenaltyOverride == nil)
            if let seekPenaltyOverride { persistence.seekPenaltyRemaining = seekPenaltyOverride }
            if startPlaying, !isPlaying { play(reconcileABS: false) }
            return
        }
        // Record the target synchronously so a second tap before the load task runs steps from it.
        let target = PendingPlaybackTarget(bookID: audiobook.id, trackIndex: trackIndex, time: time, autoplay: autoplay)
        pendingPlaybackTarget = target
        Task { [weak self] in
            // Pause or a newer chapter request can cancel this before its task starts.
            guard let self, self.pendingPlaybackTarget == target else { return }
            await self.load(
                audiobook: audiobook,
                trackIndex: trackIndex,
                time: time,
                autoplay: autoplay,
                startsRewindBreak: false,
                seekPenaltyOverride: seekPenaltyOverride
            )
        }
    }

    /// True while the player is playing or a load that will start playing is pending.
    private var hasPlayIntent: Bool {
        isPlaying || (pendingPlaybackTarget?.autoplay ?? false)
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
        refreshChapterSleepBoundary()
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

    /// Steps back from the navigation position (so taps during a pending load stack) and crosses
    /// into earlier tracks. A paused book stays paused.
    func skipBackward() {
        let isSavingProgress = persistence.seekPenaltyRemaining == 0
        let position = navigationPosition
        let target = RewindPosition.target(
            trackIndex: position.trackIndex,
            time: position.time,
            seconds: skipBackSeconds,
            trackDurations: currentAudiobook?.sortedTracks.map(\.duration) ?? []
        )
        if pendingPlaybackTarget == nil, target.trackIndex == currentTrackIndex {
            seek(to: target.time, applyProgressPenalty: !isSavingProgress)
            return
        }
        navigate(
            toTrack: target.trackIndex,
            time: target.time,
            autoplay: hasPlayIntent,
            seekPenaltyOverride: Self.rewindPenalty(isSavingProgress: isSavingProgress)
        )
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

    /// Pass `persist: false` for live slider drags, then call again with `persist: true` when the
    /// drag ends, so one gesture makes one SwiftData save and one widget reload.
    func setPlaybackRate(_ newRate: Double, persist: Bool = true) {
        let rate = Self.normalizedPlaybackRate(newRate)
        playbackRate = rate
        if isPlaying {
            player.rate = Float(rate)
        }
        guard persist else { return }
        currentAudiobook?.playbackRate = rate
        persistPlayback(force: true)
        updateNowPlayingInfo()
    }

    /// Rebuilds the cached chapter list and updates Now Playing after a book's title or author changes.
    func refreshMetadataIfCurrent(_ audiobook: Audiobook) {
        guard currentAudiobook?.id == audiobook.id else { return }
        rebuildChapters()
        updateNowPlayingInfo()
    }

    func setSleepTimer(seconds: Double?) {
        sleepTimerTask?.cancel()
        sleepTimerEndsAt = nil
        sleepAtChapterEnd = seconds == SleepTimerOption.endOfChapter.rawValue
        refreshChapterSleepBoundary()
        if sleepAtChapterEnd { return }
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

    var chapterSleepRemaining: Double {
        guard let end = sleepChapterEnd, let book = currentAudiobook else { return 0 }
        let position = navigationPosition
        let globalTime = AudiobookshelfLibraryService.globalTime(
            trackIndex: position.trackIndex, timeInTrack: position.time,
            trackDurations: book.sortedTracks.map(\.duration)
        )
        return TimeFormatter.speedAdjustedSeconds(max(0, end - globalTime), rate: playbackRate)
    }

    private func refreshChapterSleepBoundary() {
        guard sleepAtChapterEnd, let book = currentAudiobook, let chapter = currentChapter else {
            sleepChapterEnd = nil
            player.currentItem?.forwardPlaybackEndTime = .invalid
            return
        }
        let durations = book.sortedTracks.map(\.duration)
        let end = AudiobookshelfLibraryService.globalTime(
            trackIndex: chapter.trackIndex, timeInTrack: chapter.start,
            trackDurations: durations
        ) + chapter.duration
        sleepChapterEnd = end
        let trackStart = durations.prefix(currentTrackIndex).reduce(0, +)
        let endInTrack = end - trackStart
        // AVPlayer itself clamps rendering here, including in the background and for streams.
        // A chapter spanning files leaves intermediate items unrestricted.
        player.currentItem?.forwardPlaybackEndTime = endInTrack > 0 && endInTrack <= duration + 0.05
            ? CMTime(seconds: min(endInTrack, duration), preferredTimescale: 600)
            : .invalid
    }

    func setProgressMarker() {
        guard let audiobook = currentAudiobook else { return }
        clearJumpUndo()
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

    // MARK: - Smart Rewind

    /// Seconds since the current break began, or nil when no break is recorded (the user
    /// positioned the book, or it is playing). Unmeasurable values read as "unknown" in the policy.
    private func measuredAnchorElapsed(now: Date = .now) -> TimeInterval? {
        guard let anchor = smartRewindAnchor else { return nil }
        return Self.e2eSmartRewindElapsedOverride ?? now.timeIntervalSince(anchor)
    }

    /// Seconds since `audiobook` was last audible, for a fresh load. Falls back to the saved
    /// `lastPlayedAt` on a cold start, and to NaN (unknown, so a full rewind) with neither.
    private func measuredFreshLoadElapsed(for audiobook: Audiobook, now: Date = .now) -> TimeInterval {
        if let override = Self.e2eSmartRewindElapsedOverride { return override }
        guard let last = lastAudibleAt[audiobook.id] ?? audiobook.lastPlayedAt else { return .nan }
        return now.timeIntervalSince(last)
    }

    /// E2E fixture launches replace every measured break with `-e2e-smart-rewind-elapsed <seconds>`.
    private static var e2eSmartRewindElapsedOverride: TimeInterval? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-e2e-fixture"),
           let index = arguments.firstIndex(of: "-e2e-smart-rewind-elapsed"),
           arguments.indices.contains(index + 1),
           let override = Double(arguments[index + 1]) {
            return override
        }
        #endif
        return nil
    }

    // MARK: - Undo jump

    /// Whether the "Back to 14:22" pill should show: an undo point exists for this book and the
    /// playhead has left it.
    var isJumpUndoVisible: Bool {
        guard let undo = jumpUndo, let book = currentAudiobook, book.id == undo.bookID else { return false }
        let durations = book.sortedTracks.map(\.duration)
        let position = navigationPosition
        let playhead = AudiobookshelfLibraryService.globalTime(
            trackIndex: position.trackIndex, timeInTrack: position.time, trackDurations: durations
        )
        let point = AudiobookshelfLibraryService.globalTime(
            trackIndex: undo.trackIndex, timeInTrack: undo.time, trackDurations: durations
        )
        return !JumpUndoPolicy.isNearUndoPoint(playhead: playhead, undoPoint: point)
    }

    /// Where the player is now. Take it before a scrub starts or a chapter is tapped.
    func makeJumpUndoSnapshot() -> JumpUndoSnapshot {
        let position = navigationPosition
        return JumpUndoSnapshot(
            bookID: currentAudiobook?.id,
            trackIndex: position.trackIndex,
            time: position.time,
            chapterIndex: currentChapterIndex,
            seekPenaltyRemaining: persistence.seekPenaltyRemaining
        )
    }

    /// Call after the seek or chapter jump. Records nothing for a jump of 5 s or less. While an
    /// undo for this book is live it keeps the original point and only extends its lifetime, so
    /// several drags undo back to where the user started.
    func recordJumpUndo(from snapshot: JumpUndoSnapshot) {
        guard let book = currentAudiobook, snapshot.bookID == book.id else { return }
        let durations = book.sortedTracks.map(\.duration)
        let position = navigationPosition
        let before = AudiobookshelfLibraryService.globalTime(
            trackIndex: snapshot.trackIndex, timeInTrack: snapshot.time, trackDurations: durations
        )
        let after = AudiobookshelfLibraryService.globalTime(
            trackIndex: position.trackIndex, timeInTrack: position.time, trackDurations: durations
        )
        guard JumpUndoPolicy.isWorthRecording(from: before, to: after) else { return }
        let expiresAt = Date.now.addingTimeInterval(JumpUndoPolicy.lifetime)
        if let existing = jumpUndo, existing.bookID == book.id {
            jumpUndo = JumpUndo(
                bookID: existing.bookID, trackIndex: existing.trackIndex, time: existing.time,
                chapterIndex: existing.chapterIndex, seekPenaltyRemaining: existing.seekPenaltyRemaining,
                expiresAt: expiresAt
            )
        } else {
            jumpUndo = JumpUndo(
                bookID: book.id, trackIndex: snapshot.trackIndex, time: snapshot.time,
                chapterIndex: snapshot.chapterIndex, seekPenaltyRemaining: snapshot.seekPenaltyRemaining,
                expiresAt: expiresAt
            )
        }
        jumpUndoExpiryTask?.cancel()
        jumpUndoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(JumpUndoPolicy.lifetime))
            guard !Task.isCancelled else { return }
            self?.jumpUndo = nil
            self?.jumpUndoExpiryTask = nil
        }
    }

    /// Returns to the undo point and clears the pill. Plays only if the book was playing (or a
    /// playing load was pending), and restores the seek penalty the jump replaced.
    func undoJump() {
        guard let undo = jumpUndo else { return }
        let resumesPlaying = hasPlayIntent
        clearJumpUndo()
        guard let book = currentAudiobook, book.id == undo.bookID else { return }
        navigate(
            toTrack: undo.trackIndex,
            time: undo.time,
            autoplay: resumesPlaying,
            seekPenaltyOverride: undo.seekPenaltyRemaining
        )
    }

    func dismissJumpUndo() {
        clearJumpUndo()
    }

    private func clearJumpUndo() {
        jumpUndoExpiryTask?.cancel()
        jumpUndoExpiryTask = nil
        if jumpUndo != nil { jumpUndo = nil }
    }

    // MARK: - Private

    private func load(
        audiobook: Audiobook,
        trackIndex: Int,
        time: Double,
        autoplay: Bool,
        isAudiobookshelfRecovery: Bool = false,
        startsRewindBreak: Bool = true,
        seekPenaltyOverride: Double? = nil
    ) async {
        guard audiobook.sortedTracks.indices.contains(trackIndex) else { return }
        guard let track = audiobook.sortedTracks[safe: trackIndex] else { return }

        // Switching books: stamp the outgoing book's chunk now, before any await, so its createdAt
        // is when listening actually ended rather than when the new book finished loading.
        if let outgoing = currentAudiobook, outgoing.id != audiobook.id {
            sessionRecorder.end(context: modelContext)
        }

        absResumeGeneration &+= 1
        let loadToken = beginLoad()
        pendingPlaybackTarget = PendingPlaybackTarget(
            bookID: audiobook.id, trackIndex: trackIndex, time: time, autoplay: autoplay
        )
        audiobookshelfRecoveryLoadToken = isAudiobookshelfRecovery ? loadToken : nil
        // An override waits for the commit: a load that is superseded must not leave its penalty behind.
        if seekPenaltyOverride == nil {
            persistence.seekPenaltyRemaining = PlaybackPersistence.progressSeekPenalty
        }
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
            if let seekPenaltyOverride {
                persistence.seekPenaltyRemaining = seekPenaltyOverride
            }
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
                                            autoplay: resumePlaying, isAudiobookshelfRecovery: true,
                                            startsRewindBreak: false)
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
                // Playing from here: no break to measure, and no rewind on top of the target.
                smartRewindAnchor = nil
                play(reconcileABS: false)
            } else {
                pauseCurrentItemWithoutInvalidatingLoad()
                clearLoadingPlayback(for: audiobook.id)
                // A book that opens paused (restored, or Play Later) starts its break now; a load
                // that only positions a book the user is already in must not restart it.
                if startsRewindBreak { smartRewindAnchor = .now }
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
                    self.lastAudibleAt[bookID] = Date()
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
            let endedItem = notification.object as? AVPlayerItem
            Task { @MainActor in
                guard endedItem === self.player.currentItem else { return }
                if self.sleepAtChapterEnd, let end = self.sleepChapterEnd,
                   let book = self.currentAudiobook {
                    let trackStart = book.sortedTracks.prefix(self.currentTrackIndex).reduce(0) { $0 + $1.duration }
                    let endInTrack = end - trackStart
                    // Ignore stale end notifications after a seek retargeted the timer.
                    if endInTrack <= self.duration + 0.05,
                       self.player.currentTime().seconds >= endInTrack - 0.05 {
                        self.pendingSeek = nil
                        self.currentTime = min(endInTrack, self.duration)
                        self.pause()
                        self.setSleepTimer(seconds: nil)
                        if endInTrack >= self.duration - 0.05 {
                            if self.canGoToNextTrack {
                                self.chapterSleepEndedItem = endedItem
                            } else {
                                self.markCurrentBookFinished()
                            }
                        }
                        return
                    }
                    if endInTrack <= self.duration + 0.05 { return }
                }
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
        clearJumpUndo()
        setSleepTimer(seconds: nil)
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
        bookFinishedSink()
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
