//
//  AudiobookDetailView.swift
//  Ebooker
//

import SwiftData
import SwiftUI

private enum DetailTab: String, CaseIterable {
    case tracks = "Tracks"
    case moments = "Moments"
}

struct AudiobookDetailView: View {
    let audiobook: Audiobook
    let openPlayer: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: DetailTab = .tracks

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actionButtons
                tabSection
            }
            .padding(20)
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(audiobook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if player.currentAudiobook?.id == audiobook.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Player") {
                        openPlayer()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            cover

            VStack(alignment: .leading, spacing: 10) {
                Text(audiobook.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)

                Text(audiobook.displayAuthor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(currentTimestampLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                // Slim progress capsule
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 5)
                        Capsule()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: geo.size.width * audiobook.progress, height: 5)
                    }
                }
                .frame(height: 5)

                Text(progressSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await player.startPlayback(for: audiobook)
                    openPlayer()
                }
            } label: {
                Label(audiobook.lastPlayedAt == nil ? "Play" : "Resume", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Color.cream)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await player.restart(audiobook)
                    openPlayer()
                }
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab Section

    private var tabSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabPicker
            if selectedTab == .tracks {
                ForEach(audiobook.sortedTracks) { track in
                    AudiobookTrackRow(audiobook: audiobook, track: track, openPlayer: openPlayer)
                }
            } else {
                momentsSection
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedTab == tab
                                ? Color.primary.opacity(0.1)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.cardWhite, in: Capsule())
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }

    // MARK: - Moments Section

    private var momentsSection: some View {
        VStack(spacing: 10) {
            resumeAnchorRow
            let saved = audiobook.moments.sorted { $0.createdAt > $1.createdAt }
            if saved.isEmpty {
                Text("Tap the bookmark in the player to save a moment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(saved) { moment in
                    MomentRow(audiobook: audiobook, moment: moment, openPlayer: openPlayer) {
                        modelContext.delete(moment)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resumeAnchorRow: some View {
        if let progressTrackIndex = audiobook.progressTrackIndex,
           let progressTime = audiobook.progressTime {
            Button {
                Task {
                    await player.playTrack(at: progressTrackIndex, in: audiobook, time: progressTime)
                    openPlayer()
                }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        let subtitle: String = {
                            var parts = TimeFormatter.clockString(seconds: progressTime)
                            if let updatedAt = audiobook.progressUpdatedAt {
                                parts += " · \(TimeFormatter.relativeDateString(for: updatedAt))"
                            }
                            return parts
                        }()
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.primary)
                        .font(.title3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cover

    private var cover: some View {
        Group {
            if let coverArtData = audiobook.coverArtData, let image = UIImage(data: coverArtData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 130, height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    // MARK: - Helpers

    private var currentTimestampLabel: String {
        let currentTime: Double
        if player.currentAudiobook?.id == audiobook.id {
            currentTime = player.currentTime
        } else {
            currentTime = audiobook.currentTime
        }
        return "at \(TimeFormatter.clockString(seconds: currentTime))"
    }

    private var progressSummary: String {
        if audiobook.isFinished { return "Finished" }
        let pct = Int((audiobook.progress * 100).rounded())
        let remaining = TimeFormatter.durationSummary(seconds: audiobook.remainingDuration)
        return "\(pct)% · \(remaining) remaining"
    }
}

// MARK: - Moment Row

private struct MomentRow: View {
    let audiobook: Audiobook
    let moment: Moment
    let openPlayer: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var isRenaming = false
    @State private var renameInput = ""

    var body: some View {
        Button {
            Task {
                await player.playTrack(at: moment.trackIndex, in: audiobook, time: moment.time)
                openPlayer()
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "flag.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(moment.label)
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)

                    Text(TimeFormatter.clockString(seconds: moment.time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameInput = moment.label
                isRenaming = true
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Rename Moment", isPresented: $isRenaming) {
            TextField("Moment name", text: $renameInput)
            Button("Save") {
                let trimmed = renameInput.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    moment.label = trimmed
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Track Row

private struct AudiobookTrackRow: View {
    let audiobook: Audiobook
    let track: AudioTrack
    let openPlayer: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        Button {
            Task {
                await player.playTrack(at: track.orderIndex, in: audiobook)
                openPlayer()
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Text("\(track.orderIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)

                    Text(TimeFormatter.clockString(seconds: track.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if player.currentAudiobook?.id == audiobook.id, player.currentTrackIndex == track.orderIndex {
                    Image(systemName: "waveform")
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                } else {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
