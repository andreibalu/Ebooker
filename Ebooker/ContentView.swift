//
//  ContentView.swift
//  Ebooker
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum LibraryTab {
    case favorites
    case allBooks
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var player: AudioPlayerManager
    @Query private var audiobooks: [Audiobook]

    @AppStorage("librarySortOption") private var sortOptionRawValue = LibrarySortOption.recent.rawValue
    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue

    @State private var selectedTab: LibraryTab = .allBooks
    @State private var isImporterPresented = false
    @State private var pendingImport: PendingImportSelection?
    @State private var urlsHoldingSecurityAccess: [URL] = []
    @State private var isPlayerPresented = false
    @State private var isSettingsPresented = false
    @State private var deleteCandidate: Audiobook?
    @State private var renameCandidate: Audiobook?
    @State private var renameTitleInput: String = ""
    @State private var alertMessage = ""
    @State private var isShowingAlert = false

    private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 16)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                libraryHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                tabPicker
                    .padding(.horizontal, 20)

                Divider()
                    .padding(.horizontal, 20)

                libraryContent
            }
            .background(Color.cream.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .safeAreaInset(edge: .bottom) {
            if player.currentAudiobook != nil {
                MiniPlayerBar {
                    isPlayerPresented = true
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleImportSelection(result)
        }
        .sheet(item: $pendingImport, onDismiss: {
            releaseSecurityScopedAccess()
            pendingImport = nil
        }) { pending in
            ImportAudiobookSheet(pending: pending) { title, author in
                try importAudiobook(pending, title: title, author: author)
            }
        }
        .sheet(isPresented: $isPlayerPresented) {
            PlayerView()
                .environmentObject(player)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .alert("Delete Audiobook?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                deleteAudiobook()
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text("This removes the audiobook from your library and deletes its imported audio files.")
        }
        .alert("Rename Audiobook", isPresented: Binding(
            get: { renameCandidate != nil },
            set: { if !$0 { renameCandidate = nil } }
        )) {
            TextField("Book title", text: $renameTitleInput)
            Button("Save") {
                let trimmed = renameTitleInput.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    renameCandidate?.title = trimmed
                }
                renameCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                renameCandidate = nil
            }
        }
        .alert("Something Went Wrong", isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            player.configure(modelContext: modelContext)
            player.applyPlaybackDefaults(
                resumeBacktrack: resumeBacktrackSeconds,
                skipBack: skipBackSeconds,
                skipForward: skipForwardSeconds
            )
        }
        .onChange(of: resumeBacktrackSeconds) { _, newValue in
            player.applyPlaybackDefaults(
                resumeBacktrack: newValue,
                skipBack: skipBackSeconds,
                skipForward: skipForwardSeconds
            )
        }
        .onChange(of: skipBackSeconds) { _, newValue in
            player.applyPlaybackDefaults(
                resumeBacktrack: resumeBacktrackSeconds,
                skipBack: newValue,
                skipForward: skipForwardSeconds
            )
        }
        .onChange(of: skipForwardSeconds) { _, newValue in
            player.applyPlaybackDefaults(
                resumeBacktrack: resumeBacktrackSeconds,
                skipBack: skipBackSeconds,
                skipForward: newValue
            )
        }
        .onChange(of: player.playerErrorMessage) { _, newValue in
            guard let newValue else { return }
            presentAlert(message: newValue)
            player.playerErrorMessage = nil
        }
    }

    // MARK: - Header

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            // Book count badge
            ZStack {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 48, height: 48)
                Text("\(audiobooks.count)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.cream)
            }

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text("My Library")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(audiobooks.count) audiobook\(audiobooks.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toolbar buttons: Sort | Settings | Add
            HStack(spacing: 6) {
                Menu {
                    Picker("Sort by", selection: $sortOptionRawValue) {
                        ForEach(LibrarySortOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } label: {
                    toolbarIconButton(systemName: "arrow.up.arrow.down")
                }

                Button {
                    isSettingsPresented = true
                } label: {
                    toolbarIconButton(systemName: "slider.horizontal.3")
                }

                Button {
                    isImporterPresented = true
                } label: {
                    toolbarIconButton(systemName: "plus")
                }
            }
        }
    }

    private func toolbarIconButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .frame(width: 36, height: 36)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton(title: "Favorites", tab: .favorites)
            tabButton(title: "All Books", tab: .allBooks)
        }
        .padding(.bottom, 1)
    }

    private func tabButton(title: String, tab: LibraryTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.top, 12)

                Rectangle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Library Content

    @ViewBuilder
    private var libraryContent: some View {
        let books = displayedBooks
        if books.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(books) { audiobook in
                        NavigationLink {
                            AudiobookDetailView(audiobook: audiobook) {
                                isPlayerPresented = true
                            }
                        } label: {
                            AudiobookCardView(
                                audiobook: audiobook,
                                isCurrentlyPlaying: player.currentAudiobook?.id == audiobook.id
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Resume", systemImage: "play.fill") {
                                Task {
                                    await player.startPlayback(for: audiobook)
                                    try? await Task.sleep(for: .milliseconds(600))
                                    isPlayerPresented = true
                                }
                            }

                            Button(audiobook.isFavorite ? "Unfavorite" : "Favorite", systemImage: audiobook.isFavorite ? "heart.slash" : "heart") {
                                audiobook.isFavorite.toggle()
                            }

                            Button("Rename", systemImage: "pencil") {
                                renameTitleInput = audiobook.title
                                renameCandidate = audiobook
                            }

                            Button(role: .destructive) {
                                deleteCandidate = audiobook
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Computed

    private var displayedBooks: [Audiobook] {
        let base: [Audiobook]
        if selectedTab == .favorites {
            base = audiobooks.filter { $0.isFavorite }
        } else {
            base = Array(audiobooks)
        }
        return sorted(base)
    }

    private func sorted(_ books: [Audiobook]) -> [Audiobook] {
        switch LibrarySortOption(rawValue: sortOptionRawValue) ?? .recent {
        case .recent:
            books.sorted {
                let lhs = $0.lastPlayedAt ?? $0.createdAt
                let rhs = $1.lastPlayedAt ?? $1.createdAt
                return lhs > rhs
            }
        case .title:
            books.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .author:
            books.sorted {
                let left = $0.author.isEmpty ? $0.title : $0.author
                let right = $1.author.isEmpty ? $1.title : $1.author
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
        case .duration:
            books.sorted { $0.totalDuration > $1.totalDuration }
        case .dateAdded:
            books.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { newValue in
                if !newValue { deleteCandidate = nil }
            }
        )
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyState: some View {
        if selectedTab == .favorites {
            ContentUnavailableView {
                Label("No Favorites Yet", systemImage: "heart")
            } description: {
                Text("Tap the heart on any book to save it here.")
            }
        } else {
            ContentUnavailableView {
                Label("Your Library Is Empty", systemImage: "books.vertical")
            } description: {
                Text("Import one big audio file or a full set of chapter files from the Files app.")
            } actions: {
                Button("Import Audiobook") {
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Import / Delete

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let audioURLs = urls
                .filter { !$0.hasDirectoryPath }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !audioURLs.isEmpty else {
                presentAlert(message: "Choose at least one audio file.")
                return
            }
            let accessed: [URL] = audioURLs.filter { $0.startAccessingSecurityScopedResource() }
            urlsHoldingSecurityAccess = accessed
            Task {
                do {
                    pendingImport = try await LibraryImportService.prepareImport(from: audioURLs)
                } catch {
                    releaseSecurityScopedAccess()
                    presentAlert(message: error.localizedDescription)
                }
            }
        case .failure(let error):
            presentAlert(message: error.localizedDescription)
        }
    }

    private func releaseSecurityScopedAccess() {
        for url in urlsHoldingSecurityAccess {
            url.stopAccessingSecurityScopedResource()
        }
        urlsHoldingSecurityAccess = []
    }

    private func importAudiobook(_ pending: PendingImportSelection, title: String, author: String) throws {
        _ = try LibraryImportService.importAudiobook(
            from: pending,
            title: title,
            author: author,
            modelContext: modelContext
        )
        pendingImport = nil
        releaseSecurityScopedAccess()
    }

    private func deleteAudiobook() {
        guard let deleteCandidate else { return }
        do {
            try LibraryImportService.deleteAudiobook(deleteCandidate, modelContext: modelContext)
            self.deleteCandidate = nil
        } catch {
            presentAlert(message: error.localizedDescription)
        }
    }

    private func presentAlert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}
