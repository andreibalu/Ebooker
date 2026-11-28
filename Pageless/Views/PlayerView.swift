//
//  PlayerView.swift
//  Pageless
//

import SwiftData
import SwiftUI

struct PlayerView: View {
    var onDismiss: (() -> Void)? = nil
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat, CGFloat) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore
    @EnvironmentObject private var equalizer: AudioEqualizerService

    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartMomentNaming") private var useSmartMomentNaming = false
    @AppStorage("playerScrubberShowsChapter") private var scrubberShowsChapter = false

    @State private var viewModel = PlayerViewModel()
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    /// Chapter range captured when a drag starts. Playback can cross into the next chapter
    /// mid-drag, and a live range would then clamp the thumb into that chapter.
    @State private var scrubChapterRange: ClosedRange<Double>?
    @State private var scrubUndoSnapshot: JumpUndoSnapshot?
    @State private var undoHapticTrigger = 0
    @State private var showProgressConfirmation = false
    @State private var showEqualizer = false
    @State private var showChapters = false
    @State private var showPlaybackSpeed = false

    private var useSmartSave: Bool {
        #if DEBUG
        if E2EFixtures.smartSaveEnabled { return true }
        #endif
        return plusEntitlement.isPlus
            && useLocalAIFeatures
            && useSmartMomentNaming
            && AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private var presetRates: [Double] { AudioPlayerManager.playerPresetPlaybackRates }

    private var activeChapterRange: ClosedRange<Double>? {
        if isScrubbing { return scrubChapterRange }
        return scrubberShowsChapter ? player.currentTrackChapterRange : nil
    }

    private var scrubberRange: ClosedRange<Double> {
        if let chapterRange = activeChapterRange {
            return chapterRange
        }
        return 0...max(player.duration, 1)
    }

    private var scrubberScopeTitle: String {
        if activeChapterRange != nil {
            return "Chapter"
        }
        let isSingleTrack = (player.currentAudiobook?.sortedTracks.count ?? 1) <= 1
        return isSingleTrack ? "Full Book" : "File"
    }

    var body: some View {
        VStack(spacing: 0) {
            topInteractiveSection(topInset: windowSafeAreaInsets.top)

            VStack(spacing: 16) {
                progressSection
                controlsSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)

            // The slot always reserves the pill's height through a hidden sizing copy (same
            // Dynamic Type cap), so the pill never overlaps Play or the quick actions at accessibility
            // sizes or 320 pt, and showing or hiding it never moves the transport controls.
            ZStack {
                undoJumpPill(chapterTitle: nil, timeString: "00:00:00", isInteractive: false)
                    .hidden()
                    .accessibilityHidden(true)
                if player.isJumpUndoVisible, let undo = player.jumpUndo {
                    undoJumpPill(for: undo)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(AppMotion.stateChangeAnimation(reduceMotion: reduceMotion), value: player.isJumpUndoVisible)
            .zIndex(1)

            quickActionsSection
                .padding(.horizontal, 28)
                .padding(.bottom, max(24, windowSafeAreaInsets.bottom + 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.cream.ignoresSafeArea())
        .contentShape(Rectangle())
        .simultaneousGesture(dismissDragGesture)
        .sheet(isPresented: $showEqualizer) {
            EqualizerSheet()
        }
        .sheet(isPresented: $showChapters) {
            ChapterListSheet()
        }
        .sheet(isPresented: $showPlaybackSpeed) {
            PlaybackSpeedSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: SaveMomentAction.savedNotificationName)) { _ in
            viewModel.flashMomentSavedConfirmation()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingMomentTime != nil },
            set: { if !$0 { viewModel.pendingMomentTime = nil } }
        )) {
            MomentEditSheet(
                title: "Name this Moment",
                isAiGenerated: viewModel.pendingMomentAiGenerated,
                nameInput: $viewModel.momentNameInput,
                noteInput: $viewModel.momentNoteInput,
                categories: $viewModel.pendingCategories,
                quoteLine: $viewModel.pendingQuoteLine,
                characters: $viewModel.pendingCharacters,
                mood: $viewModel.pendingMood,
                notice: viewModel.pendingSmartSaveNotice?.message,
                onSave: { viewModel.commitMoment(player: player, modelContext: modelContext) },
                onCancel: { viewModel.pendingMomentTime = nil }
            )
        }
        .onAppear {
            scrubValue = player.currentTime
            if useSmartSave { viewModel.prewarmSmartSave() }
        }
        .onChange(of: useSmartSave) { _, enabled in
            if enabled { viewModel.prewarmSmartSave() }
        }
        .onChange(of: player.currentTime) { _, newValue in
            if !isScrubbing {
                scrubValue = newValue
            }
        }
        .onChange(of: player.isJumpUndoVisible) { wasVisible, isVisible in
            if !wasVisible, isVisible, let undo = player.jumpUndo {
                let label = undoAccessibilityLabel(
                    chapterTitle: undoChapterTitle(for: undo),
                    timeString: undoTimeString(for: undo)
                )
                UIAccessibility.post(notification: .announcement, argument: "Undo jump available, \(label)")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: undoHapticTrigger)
    }

    // MARK: - Cover

    private func topInteractiveSection(topInset: CGFloat) -> some View {
        VStack(spacing: 18) {
            modalHeader(topInset: topInset)

            VStack(spacing: 16) {
                cover
                titleSection
            }
            .padding(.horizontal, 28)
        }
    }

    private func modalHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 44, height: 5)
                .padding(.top, 4)

            HStack(spacing: 12) {
                AirPlayRoutePickerView()
                    .frame(width: 32, height: 32)

                Spacer()

                if player.chapters.count > 1 {
                    Button {
                        showChapters = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chapters")
                    .accessibilityIdentifier("player.chapters")
                }

                Button {
                    if let onDismiss { onDismiss() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.down")
                        .accessibilityLabel("Close player")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, max(topInset, 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .background(
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.07),
                    Color.primary.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)
        )
    }

    private var cover: some View {
        Group {
            if
                let coverArtData = player.currentAudiobook?.coverArtData,
                let image = UIImage(data: coverArtData)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GeneratedCoverView(title: player.currentAudiobook?.title ?? "Unpaged")
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text(player.currentTrack?.displayTitle ?? "Choose something to play")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("player.title")

            Text(player.currentAudiobook?.displayAuthor ?? "Audiobook")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if player.isPreparingPlayback {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.amber)
                    Text("Connecting to stream…")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.amber)
            } else if let book = player.currentAudiobook, book.absItemID != nil {
                // Audiobookshelf books: the file ordinal means nothing to a listener. Name the
                // book instead (the track line above already carries the chapter).
                if let line = audiobookshelfContextLine(for: book) {
                    Text(line)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("player.bookContext")
                }
                if book.isAudiobookshelfBook && !book.isDownloaded {
                    Text("Download this book to use smart moments.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("player.smartMoments.downloadRequired")
                }
                if let chapterLine = embeddedChapterLine {
                    chapterLineText(chapterLine)
                }
            } else if let chapterLine = embeddedChapterLine {
                chapterLineText(chapterLine)
            } else {
                Text("File \(player.currentTrackIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// The playing chapter's title when it differs from the track line — i.e. a chapter inside a
    /// file (single-file m4b, Audiobookshelf server chapters). Nil for one-file-per-chapter books.
    private var embeddedChapterLine: String? {
        guard player.chapters.count > 1, let chapter = player.currentChapter else { return nil }
        let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != player.currentTrack?.displayTitle else { return nil }
        return title
    }

    private func chapterLineText(_ title: String) -> some View {
        Button {
            showChapters = true
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter: \(title)")
        .accessibilityHint("Shows all chapters")
        .accessibilityIdentifier("player.currentChapter")
    }

    /// "Frankenstein · Part 1 of 2" for multi-file books; nil for single-file books, whose track
    /// line already shows the book title (`AudioTrack.displayTitle`).
    private func audiobookshelfContextLine(for book: Audiobook) -> String? {
        let count = book.tracks.count
        guard count > 1 else { return nil }
        let part = min(player.currentTrackIndex, count - 1) + 1
        return "\(book.title) · Part \(part) of \(count)"
    }

    // MARK: - Progress

    private var progressSection: some View {
        let range = scrubberRange
        let chapterOffset = activeChapterRange?.lowerBound ?? 0
        let clampedScrub = min(max(scrubValue, range.lowerBound), range.upperBound)
        let displayedElapsed = max(clampedScrub - chapterOffset, 0)
        let rawRemaining = max(range.upperBound - clampedScrub, 0)
        let displayedRemaining = TimeFormatter.speedAdjustedSeconds(rawRemaining, rate: player.playbackRate)

        return VStack(spacing: 4) {
            ScrubSlider(
                value: $scrubValue,
                range: range,
                displayOffset: chapterOffset,
                accessibilityScopeLabel: activeChapterRange != nil ? "Chapter playback position" : "Playback position",
                onEditingChanged: { editing in
                    if editing {
                        scrubChapterRange = activeChapterRange
                        scrubUndoSnapshot = player.makeJumpUndoSnapshot()
                    }
                    isScrubbing = editing
                    if !editing {
                        player.seek(to: scrubValue)
                        if let snapshot = scrubUndoSnapshot {
                            scrubUndoSnapshot = nil
                            player.recordJumpUndo(from: snapshot)
                        }
                    }
                }
            )

            HStack(alignment: .center) {
                Text(TimeFormatter.clockString(seconds: displayedElapsed))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("player.elapsed")

                Spacer(minLength: 8)

                // `hasSubTrackChapters` alone is true in a chapter carried over from the previous
                // file, where no track-local range exists and the toggle would do nothing.
                if player.currentTrackChapterRange != nil {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            scrubberShowsChapter.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(scrubberScopeTitle)
                                .lineLimit(1)
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(activeChapterRange != nil ? Color.amber : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            activeChapterRange != nil
                                ? Color.amber.opacity(0.14)
                                : Color.primary.opacity(0.06),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    activeChapterRange != nil ? Color.amber.opacity(0.24) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(TactileScaleButtonStyle())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityLabel("Scrubber range: \(scrubberScopeTitle)")
                    .accessibilityHint("Switches scrubber between current chapter and full file")
                    .accessibilityIdentifier("player.scrubberScope")
                }

                Spacer(minLength: 8)

                Text("-" + TimeFormatter.clockString(seconds: displayedRemaining))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("player.remaining")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: scrubberShowsChapter)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: player.playbackRate)

            if let summary = player.bookPositionSummary(
                currentTrackTimeOverride: isScrubbing ? scrubValue : nil
            ) {
                Text(TimeFormatter.bookRemainingSummary(
                    fraction: summary.fraction,
                    remainingSeconds: summary.remainingSeconds,
                    rate: player.playbackRate,
                    isFinished: player.currentAudiobook?.isFinished ?? false
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.top, 2)
                .accessibilityIdentifier("player.bookRemaining")
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: player.playbackRate)
            }
        }
    }

    // MARK: - Undo Jump Pill

    private func undoJumpPill(for undo: JumpUndo) -> some View {
        undoJumpPill(
            chapterTitle: undoChapterTitle(for: undo),
            timeString: undoTimeString(for: undo),
            isInteractive: true
        )
    }

    /// `isInteractive` is false for the hidden sizing copy, which must not carry the identifiers.
    private func undoJumpPill(chapterTitle: String?, timeString: String, isInteractive: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                undoHapticTrigger += 1
                player.undoJump()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.amber)
                        .accessibilityHidden(true)

                    HStack(spacing: 0) {
                        Text("Back to ")
                            .fixedSize(horizontal: true, vertical: false)
                        if let chapterTitle {
                            Text(chapterTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(" · ")
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text(timeString)
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(TactileScaleButtonStyle())
            .accessibilityLabel(undoAccessibilityLabel(chapterTitle: chapterTitle, timeString: timeString))
            .accessibilityIdentifier(isInteractive ? "player.undoJump" : "")

            Divider()
                .frame(height: 14)
                .overlay(Color.primary.opacity(0.12))

            Button {
                player.dismissJumpUndo()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .accessibilityLabel("Dismiss undo jump")
            .accessibilityIdentifier(isInteractive ? "player.undoJump.dismiss" : "")
        }
        .background(Color.cardWhite, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.amber.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 20)
    }

    private func undoChapterTitle(for undo: JumpUndo) -> String? {
        guard let undoChapterIndex = undo.chapterIndex,
              undoChapterIndex != player.currentChapterIndex,
              player.chapters.indices.contains(undoChapterIndex) else {
            return nil
        }
        let title = player.chapters[undoChapterIndex].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func undoTimeString(for undo: JumpUndo) -> String {
        // A chapter's start is a time in its own file, so the offset only applies on that file.
        if activeChapterRange != nil,
           let undoChapterIndex = undo.chapterIndex,
           player.chapters.indices.contains(undoChapterIndex),
           player.chapters[undoChapterIndex].trackIndex == undo.trackIndex {
            let chapter = player.chapters[undoChapterIndex]
            let relativeTime = max(undo.time - chapter.start, 0)
            return TimeFormatter.clockString(seconds: relativeTime)
        }
        return TimeFormatter.clockString(seconds: undo.time)
    }

    private func undoAccessibilityLabel(chapterTitle: String?, timeString: String) -> String {
        if let chapterTitle {
            return "Back to \(chapterTitle), \(timeString)"
        }
        return "Back to \(timeString)"
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 28) {
            Button {
                player.previousChapter()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Previous chapter")
            .accessibilityIdentifier("player.previous")
            .disabled(!player.canGoToPreviousChapter)
            .opacity(player.canGoToPreviousChapter ? 1 : 0.3)

            Button {
                player.skipBackward()
            } label: {
                Image(systemName: skipBackIconName)
                    .accessibilityLabel("Skip backward")
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            Button {
                if player.isPreparingPlayback {
                    player.pause()
                } else {
                    player.togglePlayback()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 72, height: 72)
                    if player.isPreparingPlayback {
                        ProgressView()
                            .tint(Color.cream)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.cream)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.playPause")
            .accessibilityLabel(player.isPlaying ? "Pause playback" : "Play playback")

            Button {
                player.skipForward()
            } label: {
                Image(systemName: skipForwardIconName)
                    .accessibilityLabel("Skip forward")
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            Button {
                player.nextChapter()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Next chapter")
            .accessibilityIdentifier("player.next")
            .disabled(!player.canGoToNextChapter)
            .opacity(player.canGoToNextChapter ? 1 : 0.3)
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.93))
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            segmentedQuickActionsRow

            Button {
                showProgressConfirmation = true
            } label: {
                quickActionChip(
                    icon: viewModel.progressMarked ? "checkmark" : "flag.fill",
                    text: viewModel.progressMarked ? "Progress Marked!" : "Mark Progress Here",
                    filled: viewModel.progressMarked
                )
            }
            .buttonStyle(TactileScaleButtonStyle())
            .accessibilityIdentifier("player.markProgress")
            .disabled(player.currentAudiobook == nil)
            .confirmationDialog(
                "Mark Progress",
                isPresented: $showProgressConfirmation,
                actions: {
                    Button("Mark Progress", role: .destructive) {
                        viewModel.markProgress(player: player)
                    }
                    Button("Cancel", role: .cancel) { }
                },
                message: {
                    Text("This will update your progress marker to the current playback position.")
                }
            )

            Button {
                viewModel.saveMoment(
                    player: player,
                    useSmartSave: useSmartSave,
                    momentBacktrackSeconds: momentBacktrackSeconds
                )
            } label: {
                if viewModel.isProcessingSmartSave {
                    smartSaveLoadingChip
                } else {
                    quickActionChip(
                        icon: viewModel.momentSaved ? "checkmark" : "bookmark.fill",
                        text: viewModel.momentSaved ? "Saved!" : (useSmartSave ? "Smart Save Moment" : "Save Moment"),
                        filled: viewModel.momentSaved
                    )
                }
            }
            .buttonStyle(TactileScaleButtonStyle())
            .accessibilityIdentifier("player.saveMoment")
            .disabled(player.currentAudiobook == nil || viewModel.isProcessingSmartSave)
        }
    }

    private var segmentedQuickActionsRow: some View {
        let isPresetRate = presetRates.contains { abs($0 - player.playbackRate) < 0.005 }
        return HStack(spacing: 0) {
            Menu {
                Button {
                    DispatchQueue.main.async {
                        showPlaybackSpeed = true
                    }
                } label: {
                    if isPresetRate {
                        Label("Fine-Tune Speed…", systemImage: "slider.horizontal.2.square")
                    } else {
                        Label(
                            "Fine-Tune (\(PlayerQuickActionDisplay.playbackRateSymbolTitle(for: player.playbackRate)))…",
                            systemImage: "checkmark"
                        )
                    }
                }
                .accessibilityIdentifier("player.speed.custom")

                Divider()

                ForEach(presetRates, id: \.self) { rate in
                    Button {
                        player.setPlaybackRate(rate)
                    } label: {
                        let label = "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
                        if abs(rate - player.playbackRate) < 0.005 {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                compactQuickActionSegment(
                    icon: "speedometer",
                    text: playbackRateLabel,
                    filled: abs(player.playbackRate - 1.0) >= 0.005,
                    expands: true
                )
            }
            .accessibilityIdentifier("player.speed")
            .frame(maxWidth: .infinity)

            segmentDivider

            Button {
                showEqualizer = true
            } label: {
                compactQuickActionSegment(
                    icon: "slider.horizontal.3",
                    text: "EQ",
                    filled: equalizer.isEnabled,
                    expands: true
                )
            }
            .buttonStyle(TactileScaleButtonStyle())
            .disabled(player.currentAudiobook == nil)
            .accessibilityIdentifier("player.equalizer")
            .frame(width: 74)

            segmentDivider

            Menu {
                Button("Off") {
                    player.setSleepTimer(seconds: nil)
                }
                ForEach(SleepTimerOption.allCases) { option in
                    Button(option.title) {
                        player.setSleepTimer(seconds: option.rawValue)
                    }
                    .accessibilityIdentifier(option == .endOfChapter ? "player.sleep.endOfChapter" : "player.sleep.\(Int(option.rawValue))")
                }
            } label: {
                if player.sleepAtChapterEnd || player.sleepTimerEndsAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        compactQuickActionSegment(
                            icon: "moon.zzz.fill",
                            text: player.sleepAtChapterEnd
                                ? "End of chapter\n\(TimeFormatter.clockString(seconds: player.chapterSleepRemaining))"
                                : PlayerQuickActionDisplay.sleepTimerTitle(
                                    endsAt: player.sleepTimerEndsAt,
                                    now: timeline.date
                                ),
                            filled: true,
                            expands: true,
                            accented: true
                        )
                    }
                } else {
                    compactQuickActionSegment(
                        icon: "moon.zzz.fill",
                        text: "Sleep Timer",
                        filled: false,
                        expands: true,
                        accented: false
                    )
                }
            }
            .accessibilityIdentifier("player.sleep")
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var smartSaveLoadingChip: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .tint(.primary)
            Text("Analyzing…")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .foregroundStyle(.secondary)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func compactQuickActionSegment(
        icon: String,
        text: String,
        filled: Bool,
        expands: Bool,
        accented: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accented ? Color.amber : Color.primary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(text.contains("\n") ? 2 : 1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(accented ? Color.amber : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            filled
                ? (accented ? Color.amber.opacity(0.14) : Color.primary.opacity(0.08))
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accented ? Color.amber.opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .frame(maxWidth: expands ? .infinity : nil)
        .fixedSize(horizontal: !expands, vertical: false)
        .animation(.snappy(duration: 0.2), value: text)
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 22)
            .padding(.vertical, 10)
    }

    private func quickActionChip(icon: String, text: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            filled
                ? Color.primary.opacity(0.1)
                : Color.cardWhite,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Helpers

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !isScrubbing else { return }
                let dragDown = max(0, value.translation.height)
                onDragChanged?(dragDown)
            }
            .onEnded { value in
                guard !isScrubbing else { return }
                let dragDown = max(0, value.translation.height)
                let velocityDown = max(0, value.velocity.height)
                onDragEnded?(dragDown, velocityDown)
            }
    }

    private var playbackRateLabel: String {
        PlayerQuickActionDisplay.playbackRateTitle(for: player.playbackRate)
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            return .zero
        }
        return window.safeAreaInsets
    }

    private var skipBackIconName: String {
        let secs = Int(skipBackSeconds)
        let supported = [15, 30, 45]
        let closest = supported.min(by: { abs($0 - secs) < abs($1 - secs) }) ?? 30
        return "gobackward.\(closest)"
    }

    private var skipForwardIconName: String {
        let secs = Int(skipForwardSeconds)
        let supported = [15, 30, 45]
        let closest = supported.min(by: { abs($0 - secs) < abs($1 - secs) }) ?? 30
        return "goforward.\(closest)"
    }
}

// MARK: - ScrubSlider

/// iOS-Music-style scrubber. Dragging horizontally adjusts the value at full speed; the further
/// the finger moves vertically from the start point, the finer the adjustment becomes.
private struct ScrubSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var displayOffset: Double = 0
    var accessibilityScopeLabel: String = "Playback position"
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @State private var lastX: CGFloat = 0
    @State private var startY: CGFloat = 0
    @State private var scrubRate: Double = 1.0

    private let trackHeight: CGFloat = 5
    private let thumbSize: CGFloat = 16

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isDragging {
                    Text(scrubRateLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(scrubRate < 1.0 ? .primary : .secondary)
                        .transition(.opacity)
                }
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.12), value: scrubRate)
            .animation(.easeOut(duration: 0.12), value: isDragging)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let span = max(range.upperBound - range.lowerBound, 1)
                let progress = max(0, min(1, (value - range.lowerBound) / span))
                let thumbX = CGFloat(progress) * width
                let thumbDiameter: CGFloat = isDragging ? thumbSize + 6 : thumbSize

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: thumbX, height: trackHeight)

                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
                        .position(x: thumbX, y: height / 2)
                        .animation(.easeOut(duration: 0.12), value: isDragging)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if !isDragging {
                                isDragging = true
                                lastX = g.startLocation.x
                                startY = g.startLocation.y
                                onEditingChanged(true)
                            }
                            let dx = g.location.x - lastX
                            lastX = g.location.x
                            let dy = max(0, g.location.y - startY)
                            scrubRate = rateForVerticalOffset(dy)
                            let deltaValue = Double(dx / width) * span * scrubRate
                            let newValue = (value + deltaValue)
                            value = min(max(newValue, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in
                            isDragging = false
                            scrubRate = 1.0
                            onEditingChanged(false)
                        }
                )
            }
            .frame(height: 44)
            // The drag gesture is invisible to VoiceOver; expose the scrubber as one adjustable
            // element so swipe up/down seeks in fixed steps through the same commit path.
            .accessibilityElement()
            .accessibilityLabel(accessibilityScopeLabel)
            .accessibilityValue(accessibilityPosition)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(by: accessibilityStep)
                case .decrement: adjust(by: -accessibilityStep)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("player.scrubber")
        }
    }

    private let accessibilityStep: Double = 15

    private var accessibilityPosition: String {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let elapsed = max(clamped - displayOffset, 0)
        let total = max(range.upperBound - displayOffset, 0)
        return "\(TimeFormatter.clockString(seconds: elapsed)) of \(TimeFormatter.clockString(seconds: total))"
    }

    private func adjust(by delta: Double) {
        onEditingChanged(true)
        value = min(max(value + delta, range.lowerBound), range.upperBound)
        onEditingChanged(false)
    }

    private var scrubRateLabel: String {
        switch scrubRate {
        case 0.5: return "Half-Speed Scrubbing"
        case 0.25: return "Quarter-Speed Scrubbing"
        case 0.1: return "Fine Scrubbing"
        default: return "Hi-Speed Scrubbing"
        }
    }

    private func rateForVerticalOffset(_ dy: CGFloat) -> Double {
        switch dy {
        case ..<60: return 1.0
        case 60..<130: return 0.5
        case 130..<220: return 0.25
        default: return 0.1
        }
    }
}

import AVKit

struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.backgroundColor = .clear
        routePickerView.activeTintColor = UIColor(named: "AccentColor") ?? .label
        routePickerView.tintColor = .label
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No updates needed
    }
}
