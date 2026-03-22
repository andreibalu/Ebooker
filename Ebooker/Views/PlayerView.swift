//
//  PlayerView.swift
//  Ebooker
//

import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerManager

    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("momentBacktrackSeconds") private var momentBacktrackSeconds = MomentBacktrackOption.exact.rawValue
    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartMomentNaming") private var useSmartMomentNaming = false

    @State private var viewModel = PlayerViewModel()
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var showProgressConfirmation = false

    private var useSmartSave: Bool {
        useLocalAIFeatures && useSmartMomentNaming && AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private let supportedRates: [Double] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    cover
                    titleSection
                    progressSection
                    controlsSection
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)

                Spacer(minLength: 0)

                quickActionsSection
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .background(Color.cream.ignoresSafeArea())
            .navigationTitle(player.currentAudiobook?.title ?? "Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AirPlayRoutePickerView()
                        .frame(width: 32, height: 32)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.large])
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
            HStack(spacing: 12) {
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
                    quickActionChip(
                        icon: "speedometer",
                        text: "\(player.playbackRate.formatted(.number.precision(.fractionLength(0...2))))×",
                        filled: true
                    )
                }

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
                    quickActionChip(
                        icon: "moon.zzz.fill",
                        text: sleepTimerLabel,
                        filled: player.sleepTimerEndsAt != nil
                    )
                }
            }

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
            .disabled(player.currentAudiobook == nil || viewModel.isProcessingSmartSave)
        }
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

    private var sleepTimerLabel: String {
        guard let sleepTimerEndsAt = player.sleepTimerEndsAt else { return "Sleep Timer" }
        return "Stops \(TimeFormatter.relativeDateString(for: sleepTimerEndsAt))"
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
