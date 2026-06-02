//
//  AudiobookDetailView.swift
//  Pageless
//

import PhotosUI
import SwiftData
import SwiftUI

struct AudiobookDetailView: View {
    let audiobook: Audiobook
    let openPlayer: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var aiEntitlement: AIEntitlementStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(OnboardingManager.self) private var onboarding

    @AppStorage("useLocalAIFeatures") private var useLocalAIFeatures = false
    @AppStorage("useSmartSummary") private var useSmartSummary = false
    @AppStorage("shortenSummary") private var shortenSummary = false

    @State private var viewModel: AudiobookDetailViewModel
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var showCropSheet = false
    @State private var showFilterSheet = false
    @State private var tracksExpanded = false
    @State private var momentsExpanded = false
    @State private var folderSizeMB: Int?
    @State private var streamDownloadVM = StreamedBookDownloadViewModel()
    @State private var showMatchSheet = false
    @State private var hasCloudCandidates = false
    @State private var freeBackup: Audiobook?
    @State private var showFreeRestoreConfirm = false

    /// The "Match with iCloud backup" affordance only appears when sync is active (which itself
    /// requires an active iCloud subscription), this is a downloaded own book, and there's at least
    /// one cloud-only backup to match against. When the user isn't subscribed, `IcloudSyncGate` is
    /// false and the button is simply absent.
    private var canMatchWithCloud: Bool {
        IcloudSyncGate.isEnabled()
            && audiobook.isDownloaded
            && !audiobook.isFreeBook
            && hasCloudCandidates
    }

    /// Free-book counterpart: this book was added as new even though an archived iCloud backup with
    /// the same catalog id exists. The button lets the user import that backup's progress/moments.
    private var canRestoreFreeBackup: Bool {
        IcloudSyncGate.isEnabled()
            && audiobook.isFreeBook
            && freeBackup != nil
    }

    init(audiobook: Audiobook, openPlayer: @escaping () -> Void) {
        self.audiobook = audiobook
        self.openPlayer = openPlayer
        self._viewModel = State(initialValue: AudiobookDetailViewModel(audiobook: audiobook))
    }

    /// Non-`@Query` fetch (a live query on this view would re-render on a deleted model and crash):
    /// just checks whether any cloud-only own book exists to offer as a match target.
    private func refreshCloudCandidates() {
        hasCloudCandidates = OrphanRestoreService
            .fetchOrphanCandidates(modelContext: modelContext)
            .contains { $0.id != audiobook.id }
        if audiobook.isFreeBook, let catalogId = audiobook.catalogId {
            let match = OrphanRestoreService.fetchFreeBackup(catalogId: catalogId, modelContext: modelContext)
            freeBackup = match?.id == audiobook.id ? nil : match
        } else {
            freeBackup = nil
        }
    }

    private func restoreFreeBackup() {
        guard let backup = freeBackup else { return }
        do {
            try OrphanRestoreService.restoreFreeBackup(replacing: audiobook, with: backup, modelContext: modelContext)
            dismiss()
        } catch {
            // Leave the view in place; the book is unchanged on failure.
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .spotlightTarget(.p2Progress)
                if audiobook.isStreamingOnly {
                    streamingDownloadSection
                }
                resumeAnchorRow
                momentsSection
                    .spotlightTarget(.p2Moments)
                tracksDisclosureSection
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
            if canMatchWithCloud {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMatchSheet = true
                    } label: {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                    .accessibilityLabel("Match with iCloud backup")
                }
            }
            if canRestoreFreeBackup {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFreeRestoreConfirm = true
                    } label: {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                    .accessibilityLabel("Match with iCloud backup")
                }
            }
        }
        .sheet(isPresented: $showMatchSheet) {
            MatchCloudEntrySheet(localBook: audiobook) {
                dismiss()
            }
        }
        .confirmationDialog(
            "Import from iCloud backup?",
            isPresented: $showFreeRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Import Everything", role: .destructive) {
                restoreFreeBackup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current progress and moments for ‘\(audiobook.title)’ will be replaced by your iCloud backup.")
        }
        .sheet(isPresented: $showFilterSheet) {
            MomentFilterSheet(audiobook: audiobook, viewModel: viewModel)
        }
        .onAppear {
            viewModel.reconcileStoredRecap(modelContext: modelContext)
            onboarding.notifyBookImported()
            folderSizeMB = LibraryImportService.folderSizeMB(for: audiobook)
            refreshCloudCandidates()
        }
    }

    // MARK: - Streaming Download

    @ViewBuilder
    private var streamingDownloadSection: some View {
        switch streamDownloadVM.state {
        case .idle:
            Button {
                streamDownloadVM.startDownload(audiobook: audiobook, modelContext: modelContext)
            } label: {
                Label("Download for Offline", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

        case .downloading(let completed, let total):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading…")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(completed) / \(total) tracks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    .tint(.primary)
                Button("Cancel") {
                    streamDownloadVM.cancel()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

        case .complete:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Try Again") {
                    streamDownloadVM.startDownload(audiobook: audiobook, modelContext: modelContext)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                cover

                VStack(alignment: .leading, spacing: 10) {
                    Text(audiobook.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)

                    Text(audiobook.displayAuthor)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let mb = folderSizeMB {
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("\(mb) MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(currentTimestampLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    ICloudBackupBadge(style: .inlineLabel)

                    Button {
                        Task {
                            await player.startPlayback(for: audiobook)
                            openPlayer()
                        }
                    } label: {
                        Label(
                            audiobook.lastPlayedAt == nil ? "Play" : "Continue",
                            systemImage: "play.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.primary, in: Capsule())
                        .foregroundStyle(Color.cream)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    // MARK: - Moments Section

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let saved = sortedFilteredMoments
            if audiobook.moments.isEmpty {
                momentsHeader
                Text("Tap the bookmark in the player to save a moment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if saved.isEmpty {
                momentsHeader
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
                DisclosureGroup(isExpanded: $momentsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        momentsFilterChipsRow
                        VStack(spacing: 10) {
                            ForEach(saved) { moment in
                                MomentRow(audiobook: audiobook, moment: moment, openPlayer: openPlayer) {
                                    modelContext.delete(moment)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(momentsDisclosureLabel(count: saved.count))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if momentsExpanded && hasAiAnalyzedMoments {
                            filterSheetCapsuleButton
                        }
                    }
                    .padding(.vertical, 2)
                }
                .tint(.primary.opacity(0.55))
                .padding(16)
                .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            }
        }
    }

    // MARK: - Tracks

    @ViewBuilder
    private var tracksDisclosureSection: some View {
        let tracks = audiobook.sortedTracks
        if !tracks.isEmpty {
            DisclosureGroup(isExpanded: $tracksExpanded) {
                VStack(spacing: 10) {
                    ForEach(tracks) { track in
                        AudiobookTrackRow(audiobook: audiobook, track: track, openPlayer: openPlayer)
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(tracksLabel(count: tracks.count))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
            }
            .tint(.primary.opacity(0.55))
            .padding(16)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
    }

    private func tracksLabel(count: Int) -> String {
        if count == 1 { return "1 track" }
        return "\(count) tracks"
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
                        Text(progressSectionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

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

                    if smartSummaryEnabled {
                        if viewModel.isLoadingRecap {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                        } else if viewModel.recapText == nil {
                            Button {
                                Task {
                                    await viewModel.loadRecap(
                                        trackIndex: progressTrackIndex,
                                        progressTime: progressTime,
                                        includeProgressHeadline: shortenSummary,
                                        modelContext: modelContext,
                                        onSuccessfulRecap: {
                                            aiEntitlement.consumeTrialUse()
                                        }
                                    )
                                }
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
                            await player.playProgressBookmark(at: progressTrackIndex, in: audiobook, time: progressTime)
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
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - Moments / filters

    /// Opens the moment filter sheet; used in the disclosure header when expanded and in empty-state sections.
    private var filterSheetCapsuleButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
                Text("Filter")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.1), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter moments")
    }

    /// Active filter chips only (no Filter button). Sits under the “N moments” row when the list is expanded.
    @ViewBuilder
    private var momentsFilterChipsRow: some View {
        if viewModel.hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                .padding(.vertical, 2)
            }
        }
    }

    /// Empty states: still need the Filter control when AI metadata exists (no disclosure row).
    private var momentsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasAiAnalyzedMoments {
                filterSheetCapsuleButton
            }
            momentsFilterChipsRow
        }
    }

    private var sortedFilteredMoments: [Moment] {
        let sorted = audiobook.moments.sorted { $0.createdAt > $1.createdAt }
        let base: [Moment]
        if viewModel.hasActiveFilters {
            base = sorted.filter { moment in
                let matchesCategory =
                    viewModel.filterCategories.isEmpty
                    || !viewModel.filterCategories.isDisjoint(with: moment.categories)
                let momentCharacters = Set(moment.characters.map { $0.lowercased() })
                let matchesCharacter =
                    viewModel.filterCharacters.isEmpty
                    || !viewModel.filterCharacters.isDisjoint(with: momentCharacters)
                let matchesMood =
                    viewModel.filterMoods.isEmpty
                    || (moment.mood.map { viewModel.filterMoods.contains($0) } ?? false)
                return matchesCategory && matchesCharacter && matchesMood
            }
        } else {
            base = sorted
        }
        return base.filter(\.isPinned) + base.filter { !$0.isPinned }
    }

    private var hasAiAnalyzedMoments: Bool {
        audiobook.moments.contains {
            !$0.categories.isEmpty || $0.mood != nil || !$0.characters.isEmpty
        }
    }

    private func momentsDisclosureLabel(count: Int) -> String {
        var parts: [String] = []
        if count == 1 {
            parts.append("1 moment")
        } else {
            parts.append("\(count) moments")
        }
        if viewModel.hasActiveFilters {
            parts.append("filtered")
        }
        return parts.joined(separator: " · ")
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
                    GeneratedCoverView(title: audiobook.title)
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

    private var smartSummaryEnabled: Bool {
        aiEntitlement.canUseAIFeatures
            && useLocalAIFeatures
            && useSmartSummary
            && AppleIntelligenceCapability.isSmartNamingAvailable
    }

    private var progressSectionTitle: String {
        if shortenSummary, let headline = viewModel.recapProgressHeadline, !headline.isEmpty {
            return headline
        }
        return "Your Progress"
    }
}
