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
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore
    @EnvironmentObject private var equalizer: AudioEqualizerService

    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartMomentNaming") private var useSmartMomentNaming = false

    @State private var viewModel = PlayerViewModel()
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var showProgressConfirmation = false
    @State private var showEqualizer = false

    private var useSmartSave: Bool {
        aiEntitlement.canUseAIFeatures
            && useLocalAIFeatures
            && useSmartMomentNaming
            && AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private var supportedRates: [Double] { AudioPlayerManager.supportedPlaybackRates }

    var body: some View {
        VStack(spacing: 0) {
            topInteractiveSection(topInset: windowSafeAreaInsets.top)

            VStack(spacing: 16) {
                progressSection
                controlsSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)

            Spacer(minLength: 0)

            quickActionsSection
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, max(24, windowSafeAreaInsets.bottom + 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.cream.ignoresSafeArea())
        .contentShape(Rectangle())
        .simultaneousGesture(dismissDragGesture)
        .sheet(isPresented: $showEqualizer) {
            EqualizerSheet()
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
                categories: viewModel.pendingCategories,
                quoteLine: viewModel.pendingQuoteLine,
                characters: viewModel.pendingCharacters,
                mood: viewModel.pendingMood,
                onSave: { viewModel.commitMoment(player: player, modelContext: modelContext) },
                onCancel: { viewModel.pendingMomentTime = nil }
            )
        }
        .onAppear {
            scrubValue = player.currentTime
        }
        .onChange(of: player.currentTime) { _, newValue in
            if !isScrubbing {
                scrubValue = newValue
            }
        }
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
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 42, height: 5)

            HStack(spacing: 12) {
                AirPlayRoutePickerView()
                    .frame(width: 32, height: 32)

                Spacer()

                Button {
                    if let onDismiss { onDismiss() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, max(topInset, 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
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
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.95))
                    }
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text(player.currentTrack?.title ?? "Choose something to play")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(player.currentAudiobook?.displayAuthor ?? "Audiobook")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("File \(player.currentTrackIndex + 1)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { scrubValue },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        player.seek(to: scrubValue)
                    }
                }
            )
            .tint(Color.primary.opacity(0.7))

            HStack {
                Text(TimeFormatter.clockString(seconds: scrubValue))
                Spacer()
                Text("-" + TimeFormatter.clockString(seconds: max(player.duration - scrubValue, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 28) {
            Button {
                player.previousTrack()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .disabled(!player.canGoToPreviousTrack)
            .opacity(player.canGoToPreviousTrack ? 1 : 0.3)

            Button {
                player.skipBackward()
            } label: {
                Image(systemName: skipBackIconName)
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            Button {
                player.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 72, height: 72)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.cream)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            Button {
                player.skipForward()
            } label: {
                Image(systemName: skipForwardIconName)
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            Button {
                player.nextTrack()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .disabled(!player.canGoToNextTrack)
            .opacity(player.canGoToNextTrack ? 1 : 0.3)
        }
        .buttonStyle(.plain)
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
                    momentBacktrackSeconds: momentBacktrackSeconds,
                    onSuccessfulSmartAI: {
                        aiEntitlement.consumeTrialUse()
                    }
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
            .disabled(player.currentAudiobook == nil || viewModel.isProcessingSmartSave)
        }
    }

    private var segmentedQuickActionsRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(supportedRates, id: \.self) { rate in
                        Button {
                            player.setPlaybackRate(rate)
                        } label: {
                            if rate == player.playbackRate {
                                Label("\(rate.formatted(.number.precision(.fractionLength(0...2))))×", systemImage: "checkmark")
                            } else {
                                Text("\(rate.formatted(.number.precision(.fractionLength(0...2))))×")
                            }
                        }
                    }
                } label: {
                    compactQuickActionSegment(
                        icon: "speedometer",
                        text: "\(playbackRateLabel)",
                        filled: false,
                        expands: true
                    )
                }

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
                .disabled(player.currentAudiobook == nil)
            }
            .frame(maxWidth: .infinity)

            segmentDivider

            Menu {
                Button("Off") {
                    player.setSleepTimer(seconds: nil)
                }
                ForEach(SleepTimerOption.allCases) { option in
                    Button(option.title) {
                        player.setSleepTimer(seconds: option.rawValue)
                    }
                }
            } label: {
                compactQuickActionSegment(
                    icon: "moon.zzz.fill",
                    text: "Sleep Timer",
                    filled: player.sleepTimerEndsAt != nil,
                    expands: true
                )
            }
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

    private func compactQuickActionSegment(icon: String, text: String, filled: Bool, expands: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.92)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            filled ? Color.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .frame(maxWidth: expands ? .infinity : nil)
        .fixedSize(horizontal: !expands, vertical: false)
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
                let dragDown = max(0, value.translation.height)
                onDragChanged?(dragDown)
            }
            .onEnded { value in
                let dragDown = max(0, value.translation.height)
                let velocityDown = max(0, value.velocity.height)
                onDragEnded?(dragDown, velocityDown)
            }
    }

    private var playbackRateLabel: String {
        "\(player.playbackRate.formatted(.number.precision(.fractionLength(0...2))))x"
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

import AVKit

struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.backgroundColor = .clear
        routePickerView.activeTintColor = .systemBlue
        routePickerView.tintColor = .label
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No updates needed
    }
}
