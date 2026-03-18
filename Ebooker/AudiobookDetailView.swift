//
//  AudiobookDetailView.swift
//  Ebooker
//

import PhotosUI
import Speech
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
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var showCropSheet = false

    // Filter state
    @State private var filterCategories: Set<MomentCategory> = []
    @State private var filterCharacters: Set<String> = []
    @State private var filterMoods: Set<MomentMood> = []
    @State private var showFilterSheet = false

    // Recap state
    @State private var isLoadingRecap = false
    @State private var recapText: String?
    @State private var recapError: String?

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
                if hasAiAnalyzedMoments {
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
            let saved = filteredMoments
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
                        filterCategories.removeAll()
                        filterCharacters.removeAll()
                        filterMoods.removeAll()
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

    private var filteredMoments: [Moment] {
        let sorted = audiobook.moments.sorted { $0.createdAt > $1.createdAt }
        guard !filterCategories.isEmpty || !filterCharacters.isEmpty || !filterMoods.isEmpty else {
            return sorted
        }
        return sorted.filter { moment in
            let matchesCategory = filterCategories.isEmpty || !filterCategories.isDisjoint(with: moment.categories)
            let matchesCharacter = filterCharacters.isEmpty || !filterCharacters.isDisjoint(with: Set(moment.characters.map { $0.lowercased() }))
            let matchesMood = filterMoods.isEmpty || (moment.mood.map { filterMoods.contains($0) } ?? false)
            return matchesCategory && matchesCharacter && matchesMood
        }
    }

    private var hasAiAnalyzedMoments: Bool {
        audiobook.moments.contains { !$0.categories.isEmpty || $0.mood != nil || !$0.characters.isEmpty }
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
                        if isLoadingRecap {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                        } else if recapText == nil {
                            Button {
                                Task { await loadRecap(trackIndex: progressTrackIndex, progressTime: progressTime) }
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

                if let recap = recapText {
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

                if let error = recapError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func loadRecap(trackIndex: Int, progressTime: Double) async {
        isLoadingRecap = true
        defer { Task { @MainActor in isLoadingRecap = false } }

        do {
            let tracks = audiobook.sortedTracks
            guard tracks.indices.contains(trackIndex) else { return }
            let track = tracks[trackIndex]
            let fileURL = try LibraryImportService.fileURL(for: track, in: audiobook)

            let startSeconds = max(0, progressTime - 200)
            let endSeconds = progressTime
            guard endSeconds > startSeconds else { return }

            let audioURL = try await AudioExtractionService.extractSegment(
                from: fileURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds
            )
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let authStatus = await TranscriptionService.requestAuthorization()
            guard authStatus == .authorized else {
                await MainActor.run { recapError = "Speech recognition not authorized." }
                return
            }

            let transcript = try await TranscriptionService.transcribe(audioURL: audioURL)
            guard !transcript.isEmpty else {
                await MainActor.run { recapError = "Could not transcribe audio." }
                return
            }

            let recap = try await RecapService.generateRecap(
                transcript: transcript,
                audiobookTitle: audiobook.title
            )
            await MainActor.run {
                recapText = recap
                recapError = nil
            }
        } catch {
            await MainActor.run { recapError = error.localizedDescription }
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
                        .foregroundStyle(hasActiveFilters ? .primary : .secondary)
                }
                .buttonStyle(.plain)

                ForEach(Array(filterCategories), id: \.self) { cat in
                    filterChip(text: cat.displayName) {
                        filterCategories.remove(cat)
                    }
                }
                ForEach(Array(filterMoods), id: \.self) { mood in
                    filterChip(text: mood.displayName) {
                        filterMoods.remove(mood)
                    }
                }
                ForEach(Array(filterCharacters).sorted(), id: \.self) { char in
                    filterChip(text: char) {
                        filterCharacters.remove(char)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSheet
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

    private var hasActiveFilters: Bool {
        !filterCategories.isEmpty || !filterCharacters.isEmpty || !filterMoods.isEmpty
    }

    private var filterSheet: some View {
        NavigationStack {
            List {
                let availableCategories = Set(audiobook.moments.flatMap(\.categories))
                if !availableCategories.isEmpty {
                    Section("Categories") {
                        ForEach(availableCategories.sorted(by: { $0.rawValue < $1.rawValue })) { category in
                            Button {
                                if filterCategories.contains(category) {
                                    filterCategories.remove(category)
                                } else {
                                    filterCategories.insert(category)
                                }
                            } label: {
                                HStack {
                                    Text(category.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if filterCategories.contains(category) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                let availableCharacters = audiobook.castList
                if !availableCharacters.isEmpty {
                    Section("Characters") {
                        ForEach(availableCharacters, id: \.self) { character in
                            let key = character.lowercased()
                            Button {
                                if filterCharacters.contains(key) {
                                    filterCharacters.remove(key)
                                } else {
                                    filterCharacters.insert(key)
                                }
                            } label: {
                                HStack {
                                    Text(character)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if filterCharacters.contains(key) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                let availableMoods = Set(audiobook.moments.compactMap(\.mood))
                if !availableMoods.isEmpty {
                    Section("Moods") {
                        ForEach(availableMoods.sorted(by: { $0.rawValue < $1.rawValue })) { mood in
                            Button {
                                if filterMoods.contains(mood) {
                                    filterMoods.remove(mood)
                                } else {
                                    filterMoods.insert(mood)
                                }
                            } label: {
                                HStack {
                                    Text(mood.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if filterMoods.contains(mood) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                if hasActiveFilters {
                    Section {
                        Button("Clear All", role: .destructive) {
                            filterCategories.removeAll()
                            filterCharacters.removeAll()
                            filterMoods.removeAll()
                        }
                    }
                }
            }
            .navigationTitle("Filter Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilterSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

// MARK: - Moment Row

private struct MomentRow: View {
    let audiobook: Audiobook
    let moment: Moment
    let openPlayer: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var isEditing = false
    @State private var editNameInput = ""
    @State private var editNoteInput = ""

    var body: some View {
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

                if let note = moment.notes, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
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
        .onTapGesture {
            editNameInput = moment.label
            editNoteInput = moment.notes ?? ""
            isEditing = true
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isEditing) {
            MomentEditSheet(
                title: "Edit Moment",
                isAiGenerated: moment.aiGeneratedName,
                nameInput: $editNameInput,
                noteInput: $editNoteInput,
                categories: moment.categories,
                quoteLine: moment.quoteLine,
                characters: moment.characters,
                mood: moment.mood,
                onSave: {
                    let trimmedName = editNameInput.trimmingCharacters(in: .whitespaces)
                    if !trimmedName.isEmpty {
                        moment.label = trimmedName
                    }
                    let trimmedNote = editNoteInput.trimmingCharacters(in: .whitespaces)
                    moment.notes = trimmedNote.isEmpty ? nil : trimmedNote
                    isEditing = false
                },
                onCancel: { isEditing = false },
                onPlay: {
                    Task {
                        await player.playTrack(at: moment.trackIndex, in: audiobook, time: moment.time)
                        isEditing = false
                        openPlayer()
                    }
                }
            )
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
