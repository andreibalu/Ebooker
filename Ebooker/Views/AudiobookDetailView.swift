//
//  AudiobookDetailView.swift
//  Ebooker
//

import PhotosUI
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

    @State private var viewModel: AudiobookDetailViewModel
    @State private var selectedTab: DetailTab = .tracks
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var showCropSheet = false
    @State private var showFilterSheet = false

    init(audiobook: Audiobook, openPlayer: @escaping () -> Void) {
        self.audiobook = audiobook
        self.openPlayer = openPlayer
        self._viewModel = State(initialValue: AudiobookDetailViewModel(audiobook: audiobook))
    }

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
        .fullScreenCover(isPresented: $showCropSheet) {
            if let img = pendingCropImage {
                CoverCropView(
                    uiImage: img,
                    onConfirm: { cropped in
                        audiobook.coverArtData = cropped.jpegData(compressionQuality: 0.85)
                        showCropSheet = false
                        pendingCropImage = nil
                    },
                    onCancel: {
                        showCropSheet = false
                        pendingCropImage = nil
                    }
                )
            }
        }
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
        VStack(spacing: 12) {
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

            resumeAnchorRow
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
                if viewModel.hasAiAnalyzedMoments {
                    filterChipBar
                }
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
            let saved = viewModel.filteredMoments
            if audiobook.moments.isEmpty {
                Text("Tap the bookmark in the player to save a moment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if saved.isEmpty {
                VStack(spacing: 8) {
                    Text("No moments match your filters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Clear Filters") {
                        viewModel.clearFilters()
                    }
                    .font(.caption.weight(.medium))
                }
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

    // MARK: - Resume Anchor Row

    @ViewBuilder
    private var resumeAnchorRow: some View {
        if let progressTrackIndex = audiobook.progressTrackIndex,
           let progressTime = audiobook.progressTime {
            VStack(spacing: 8) {
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
                                parts += " \u{00B7} \(TimeFormatter.relativeDateString(for: updatedAt))"
                            }
                            return parts
                        }()
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if AppleIntelligenceCapability.isSmartNamingAvailable {
                        if viewModel.isLoadingRecap {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                        } else if viewModel.recapText == nil {
                            Button {
                                Task { await viewModel.loadRecap(trackIndex: progressTrackIndex, progressTime: progressTime) }
                            } label: {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.primary)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        Task {
                            await player.playTrack(at: progressTrackIndex, in: audiobook, time: progressTime)
                            openPlayer()
                        }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.primary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

                if let recap = viewModel.recapText {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Where Was I?", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(recap)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let error = viewModel.recapError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Filter UI

    private var filterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.hasActiveFilters ? .primary : .secondary)
                }
                .buttonStyle(.plain)

                ForEach(Array(viewModel.filterCategories), id: \.self) { cat in
                    filterChip(text: cat.displayName) {
                        viewModel.filterCategories.remove(cat)
                    }
                }
                ForEach(Array(viewModel.filterMoods), id: \.self) { mood in
                    filterChip(text: mood.displayName) {
                        viewModel.filterMoods.remove(mood)
                    }
                }
                ForEach(Array(viewModel.filterCharacters).sorted(), id: \.self) { char in
                    filterChip(text: char) {
                        viewModel.filterCharacters.remove(char)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showFilterSheet) {
            MomentFilterSheet(audiobook: audiobook, viewModel: viewModel)
        }
    }

    private func filterChip(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.1), in: Capsule())
        .foregroundStyle(.primary)
    }

    // MARK: - Cover

    private var cover: some View {
        PhotosPicker(
            selection: $selectedCoverItem,
            matching: .images
        ) {
            Group {
                if let coverArtData = audiobook.coverArtData, let image = UIImage(data: coverArtData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
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
            .overlay(alignment: .bottom) {
                Text("Change cover")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: selectedCoverItem) { _, newItem in
            Task {
                await loadSelectedCover(newItem)
            }
        }
        .contextMenu {
            if audiobook.coverArtData != nil {
                Button(role: .destructive) {
                    audiobook.coverArtData = nil
                } label: {
                    Label("Remove cover", systemImage: "trash")
                }
            }
        }
    }

    private func loadSelectedCover(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data) else { return }

        await MainActor.run {
            selectedCoverItem = nil
            pendingCropImage = image
            showCropSheet = true
        }
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
