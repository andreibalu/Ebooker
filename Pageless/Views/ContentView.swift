//
//  ContentView.swift
//  Pageless
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum LibraryTab {
    case favorites
    case allBooks
    case freeBooks
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboarding
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var aiEntitlementStore: AIEntitlementStore
    @Query private var audiobooks: [Audiobook]

    @AppStorage("librarySortOption") private var sortOptionRawValue = LibrarySortOption.recent.rawValue
    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue

    @Environment(FreeBookDownloadService.self) private var downloadService

    @State private var viewModel = LibraryViewModel()
    @State private var browseViewModel = BrowseLibriVoxViewModel()
    @State private var selectedTab: LibraryTab = .favorites
    @State private var isImporterPresented = false
    @State private var isPlayerPresented = false
    @State private var isSettingsPresented = false
    @State private var selectedFreeBook: FreeBookCatalogEntry?

    private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
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

            if player.currentAudiobook != nil {
                MiniPlayerBar {
                    isPlayerPresented = true
                }
            }
        }
        .spotlightOverlay(
            onboarding: onboarding,
            totalPhaseSteps: onboarding.totalStepsInPhase,
            currentPhaseIndex: onboarding.currentPhaseIndex
        )
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            viewModel.handleImportSelection(result)
        }
        .sheet(item: $viewModel.pendingImport, onDismiss: {
            viewModel.releaseSecurityScopedAccess()
            viewModel.pendingImport = nil
        }) { pending in
            ImportAudiobookSheet(pending: pending) { title, author in
                try viewModel.importAudiobook(pending, title: title, author: author, modelContext: modelContext)
                onboarding.notifyBookImported()
            }
        }
        .sheet(isPresented: $isPlayerPresented) {
            PlayerView()
                .environmentObject(player)
                .environmentObject(aiEntitlementStore)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(onRefreshCatalog: {
                browseViewModel.forceRefresh(modelContext: modelContext)
            })
            .environmentObject(aiEntitlementStore)
            .environment(onboarding)
        }
        .sheet(item: $selectedFreeBook) { entry in
            FreeBookDetailSheet(
                entry: entry,
                isDownloaded: downloadedCatalogIds.contains(entry.id),
                isDownloading: downloadService.activeDownloads.contains(entry.id),
                downloadProgress: downloadService.downloadProgress[entry.id],
                downloadError: downloadService.downloadErrors[entry.id],
                onDownload: {
                    downloadService.startDownload(entry: entry)
                },
                onCancel: {
                    downloadService.cancelDownload(catalogId: entry.id)
                }
            )
        }
        .onChange(of: onboarding.requestOpenSettings) { _, shouldOpen in
            if shouldOpen {
                isSettingsPresented = true
                onboarding.requestOpenSettings = false
            }
        }
        .onChange(of: onboarding.requestDismissSettings) { _, shouldDismiss in
            if shouldDismiss {
                isSettingsPresented = false
                onboarding.requestDismissSettings = false
            }
        }
        .alert(
            viewModel.deleteCandidate?.isFreeBook == true ? "Remove Download?" : "Remove Audiobook?",
            isPresented: deleteConfirmationBinding
        ) {
            if viewModel.deleteCandidate?.isFreeBook == true {
                Button("Remove Download", role: .destructive) {
                    if let book = viewModel.deleteCandidate {
                        viewModel.deleteFreeBook(book, modelContext: modelContext)
                        viewModel.deleteCandidate = nil
                    }
                }
            } else {
                Button("Remove from App", role: .destructive) {
                    viewModel.deleteAudiobook(alsoDeleteFiles: false, modelContext: modelContext)
                }
                Button("Also Delete Files", role: .destructive) {
                    viewModel.deleteAudiobook(alsoDeleteFiles: true, modelContext: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.deleteCandidate = nil
            }
        } message: {
            if viewModel.deleteCandidate?.isFreeBook == true {
                Text("This will remove the downloaded audiobook. You can download it again from the free books section.")
            } else {
                Text("Choose whether to remove this audiobook from Unpaged only, or also delete its imported audio files from local storage.")
            }
        }
        .alert("Rename Audiobook", isPresented: Binding(
            get: { viewModel.renameCandidate != nil },
            set: { if !$0 { viewModel.renameCandidate = nil } }
        )) {
            TextField("Book title", text: $viewModel.renameTitleInput)
            Button("Save") {
                viewModel.commitRename()
            }
            Button("Cancel", role: .cancel) {
                viewModel.renameCandidate = nil
            }
        }
        .alert("Something Went Wrong", isPresented: $viewModel.isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
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
            viewModel.presentAlert(message: newValue)
            player.playerErrorMessage = nil
        }
    }

    // MARK: - Header

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 48, height: 48)
                Text("\(audiobooks.count)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.cream)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("My Library")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

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
                .spotlightTarget(.p1Settings)

                Button {
                    isImporterPresented = true
                } label: {
                    toolbarIconButton(systemName: "plus")
                }
                .spotlightTarget(.p1AddButton)
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
            tabButton(title: "Free Books", tab: .freeBooks)
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
        if selectedTab == .freeBooks {
            BrowseLibriVoxView(onOpenPlayer: {
                isPlayerPresented = true
            }, viewModel: browseViewModel)
        } else {
            let books = displayedBooks
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(books) { audiobook in
                            audiobookGridItem(audiobook)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func audiobookGridItem(_ audiobook: Audiobook) -> some View {
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

            if !audiobook.isFreeBook {
                Button("Rename", systemImage: "pencil") {
                    viewModel.beginRename(audiobook)
                }
            }

            Button(role: .destructive) {
                viewModel.deleteCandidate = audiobook
            } label: {
                Label(audiobook.isFreeBook ? "Remove Download" : "Delete", systemImage: "trash")
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
        return viewModel.sorted(base, by: sortOptionRawValue)
    }

    private var downloadedCatalogIds: Set<String> {
        Set(audiobooks.compactMap(\.catalogId))
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deleteCandidate != nil },
            set: { newValue in
                if !newValue { viewModel.deleteCandidate = nil }
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
                Text("Import an audiobook from Files, or browse thousands of free public-domain classics.")
            } actions: {
                Button("Import Audiobook") {
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)

                Button("Browse Free Books") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .freeBooks
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
