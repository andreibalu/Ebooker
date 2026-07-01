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

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .allBooks: "Library"
        case .freeBooks: "Free Books"
        }
    }
}

@MainActor
enum LibraryBookVisibility {
    static func includes(
        bookID: UUID,
        isDownloaded: Bool,
        isFreeBook: Bool,
        isArchived: Bool,
        isFavorite: Bool,
        tab: LibraryTab,
        downloadEntry: LibriVoxDownloadManager.Entry?
    ) -> Bool {
        let normallyVisible = (isDownloaded || isFreeBook) && !isArchived
        if tab == .favorites {
            return normallyVisible && isFavorite
        }
        guard tab == .allBooks else { return false }
        if normallyVisible { return true }
        guard isFreeBook, isArchived, let downloadEntry,
              case .existing(let targetID) = downloadEntry.target
        else { return false }
        return targetID == bookID
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboarding
    @Environment(LibriVoxDownloadManager.self) private var downloadManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var aiEntitlementStore: AIEntitlementStore
    @Query private var audiobooks: [Audiobook]
    @Query(sort: \ReadingSession.date, order: .reverse) private var readingSessions: [ReadingSession]
    @Namespace private var readingStatsNamespace
    private let readingStatsMorphID = "reading-activity-heatmap"

    // Each library tab keeps its own sort preference. "librarySortOption" remains the Library
    // key so existing users keep their saved choice; Favorites gets its own independent key.
    @AppStorage("librarySortOption") private var allBooksSortRaw = LibrarySortOption.recent.rawValue
    @AppStorage("favoritesSortOption") private var favoritesSortRaw = LibrarySortOption.recent.rawValue
    // When the user chose "Free books" in onboarding, the app always opens on Free Books and the
    // tabs reorder to Favorites / Free Books / Library. Default false = unchanged behavior.
    @AppStorage("startOnFreeBooks") private var startOnFreeBooks = false
    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue

    @State private var viewModel = LibraryViewModel()
    @State private var browseViewModel = BrowseLibriVoxViewModel()
    @State private var selectedTab: LibraryTab = .favorites
    @State private var didApplyInitialTab = false
    @State private var isImporterPresented = false
    @State private var isPlayerVisible = false
    @State private var isClosingPlayer = false
    @State private var playerYOffset: CGFloat = UIScreen.main.bounds.height
    @State private var isSettingsPresented = false
    @State private var isCloudLibraryPresented = false
    private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 16)]
    private let screenHeight = UIScreen.main.bounds.height

    var body: some View {
        ZStack(alignment: .top) {
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
                    MiniPlayerBar(
                        openPlayer: openPlayer,
                        onDragChanged: handlePlayerDragChanged,
                        onDragEnded: handlePlayerDragEnded
                    )
                }
            }

            if isPlayerVisible {
                PlayerView(
                    onDismiss: closePlayer,
                    onDragChanged: handlePlayerDismissDragChanged,
                    onDragEnded: handlePlayerDismissDragEnded
                )
                    .environmentObject(player)
                    .environmentObject(aiEntitlementStore)
                    .offset(y: playerYOffset)
                    .ignoresSafeArea()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            viewModel.handleImportSelection(result, modelContext: modelContext)
        }
        .sheet(item: $viewModel.pendingImport, onDismiss: {
            viewModel.releaseSecurityScopedAccess()
            viewModel.pendingImport = nil
        }) { pending in
            ImportAudiobookSheet(pending: pending) { title, author in
                try viewModel.importAudiobook(pending, title: title, author: author, modelContext: modelContext)
            }
        }
        .sheet(item: $viewModel.restoreMatch) { candidate in
            RestoreMatchSheet(
                candidate: candidate,
                onRestore: {
                    viewModel.adoptRestoreMatch(modelContext: modelContext)
                },
                onAddAsNew: {
                    viewModel.dismissRestoreMatchAndAddAsNew()
                },
                onCancel: {
                    viewModel.cancelRestoreMatch()
                }
            )
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                onRefreshCatalog: {
                    browseViewModel.forceRefresh(modelContext: modelContext)
                },
                onResetCatalog: {
                    browseViewModel.resetCatalog(modelContext: modelContext)
                }
            )
            .environmentObject(aiEntitlementStore)
            .environment(onboarding)
        }
        .sheet(isPresented: $isCloudLibraryPresented) {
            NavigationStack {
                CloudLibraryView()
            }
            .environmentObject(player)
            .environmentObject(aiEntitlementStore)
            .environment(onboarding)
        }
        .overlay {
            // Welcome onboarding. Gated with an `if` read directly in `body` so the dependency on
            // `onboarding.isComplete` is tracked (a no-op `fullScreenCover` binding may not re-trigger),
            // and so it's present from the first frame on a cold launch (no library flash).
            if !onboarding.isComplete {
                OnboardingFlowView { homeTab in
                    selectedTab = homeTab
                    withAnimation(.easeInOut(duration: 0.4)) {
                        onboarding.complete()
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .alert(
            deleteAlertTitle,
            isPresented: deleteConfirmationBinding
        ) {
            if viewModel.deleteCandidate?.isStreamingOnly == true {
                Button("Remove from Library", role: .destructive) {
                    if let book = viewModel.deleteCandidate {
                        viewModel.deleteFreeBook(book, modelContext: modelContext)
                        viewModel.deleteCandidate = nil
                    }
                }
            } else if viewModel.deleteCandidate?.isFreeBook == true {
                Button("Remove Download", role: .destructive) {
                    if let book = viewModel.deleteCandidate {
                        viewModel.deleteFreeBook(book, modelContext: modelContext)
                        viewModel.deleteCandidate = nil
                    }
                }
            } else if IcloudSyncGate.isEnabled() {
                Button("Remove from this iPhone", role: .destructive) {
                    viewModel.softDeleteAudiobook(modelContext: modelContext)
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
            if viewModel.deleteCandidate?.isStreamingOnly == true {
                if IcloudSyncGate.isEnabled() {
                    Text("Removes this book from your library on this iPhone. Your progress and bookmarks stay in your iCloud Library, and you can stream it again anytime.")
                } else {
                    Text("This will remove the book from your library. You can add it again from the free books section.")
                }
            } else if viewModel.deleteCandidate?.isFreeBook == true {
                if IcloudSyncGate.isEnabled() {
                    Text("Removes the download from this iPhone. Your progress and bookmarks stay in your iCloud Library, and you can stream or re-download it anytime.")
                } else {
                    Text("This will remove the downloaded audiobook. You can download it again from the free books section.")
                }
            } else if IcloudSyncGate.isEnabled() {
                Text("Removes the audio from this iPhone. The book stays in your iCloud Library, and you can restore it anytime.")
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
        .alert(viewModel.alertTitle, isPresented: $viewModel.isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
        .onAppear {
            // One-time launch-tab application for relaunched users (first-run routing is handled by
            // the onboarding onFinish closure). Free-books choosers open on Free Books every launch.
            if !didApplyInitialTab {
                didApplyInitialTab = true
                if onboarding.isComplete && startOnFreeBooks {
                    selectedTab = .freeBooks
                }
            }
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
                // iCloud Library — only for active subscribers, who are the only users with books
                // backed up to iCloud to browse. Opens the full backed-up library.
                if ICloudSubscriptionStore.isSubscribedAtLaunch() {
                    Button {
                        isCloudLibraryPresented = true
                    } label: {
                        toolbarIconButton(systemName: "icloud")
                    }
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

    /// Tab order is fixed for own-book users (Favorites / Library / Free Books). Users who chose
    /// "Free books" in onboarding get Free Books promoted to the center (Favorites / Free Books / Library).
    private var tabOrder: [LibraryTab] {
        startOnFreeBooks ? [.favorites, .freeBooks, .allBooks] : [.favorites, .allBooks, .freeBooks]
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(tabOrder, id: \.self) { tab in
                tabPickerButton(for: tab)
            }
        }
        .padding(.bottom, 1)
    }

    @ViewBuilder
    private func tabPickerButton(for tab: LibraryTab) -> some View {
        switch tab {
        case .favorites:
            sortableTabButton(title: "Favorites", tab: .favorites, sortRaw: $favoritesSortRaw)
        case .allBooks:
            sortableTabButton(title: tab.title, tab: .allBooks, sortRaw: $allBooksSortRaw)
        case .freeBooks:
            tabButton(title: "Free Books", tab: .freeBooks)
        }
    }

    /// A tab that owns its own sort preference. Tapping it while it's *not* the active tab simply
    /// switches to it; tapping it *while already active* opens its sort menu (a chevron appears beside
    /// the title to hint this). Each sortable tab keeps an independent `sortRaw`.
    @ViewBuilder
    private func sortableTabButton(title: String, tab: LibraryTab, sortRaw: Binding<String>) -> some View {
        let isSelected = selectedTab == tab
        Group {
            if isSelected {
                Menu {
                    Picker("Sort by", selection: sortRaw) {
                        ForEach(LibrarySortOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } label: {
                    tabColumn(title: title, isSelected: true, showsChevron: true)
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    tabColumn(title: title, isSelected: false, showsChevron: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tabColumn(title: String, isSelected: Bool, showsChevron: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)

            Rectangle()
                .fill(isSelected ? Color.primary : Color.clear)
                .frame(height: 2)
                .cornerRadius(1)
        }
        .contentShape(Rectangle())
    }

    private func tabButton(title: String, tab: LibraryTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            tabColumn(title: title, isSelected: isSelected, showsChevron: false)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Library Content

    @ViewBuilder
    private var libraryContent: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabOrder, id: \.self) { tab in
                tabPage(for: tab)
                    .tag(tab)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func tabPage(for tab: LibraryTab) -> some View {
        switch tab {
        case .favorites:
            booksGrid(for: .favorites)
        case .allBooks:
            booksGrid(for: .allBooks)
        case .freeBooks:
            BrowseLibriVoxView(onOpenPlayer: {
                openPlayer()
            }, viewModel: browseViewModel)
        }
    }

    @ViewBuilder
    private func booksGrid(for tab: LibraryTab) -> some View {
        let books = displayedBooks(for: tab)
        ScrollView {
            LazyVStack(spacing: 16) {
                if tab == .allBooks {
                    LibriVoxDownloadSection()
                }
                if tab == .favorites { readingActivityHeader }

                if books.isEmpty {
                    emptyState(for: tab)
                        .padding(.top, 24)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(books) { audiobook in
                            audiobookGridItem(audiobook)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var readingActivityHeader: some View {
        let stats = ReadingStats.compute(
            sessions: readingSessions,
            booksFinished: audiobooks.filter { $0.isFinished }.count
        )
        if stats.hasAnyActivity {
            NavigationLink {
                ReadingStatsView(stats: stats, palette: .amber)
                    .navigationTransition(.zoom(sourceID: readingStatsMorphID, in: readingStatsNamespace))
            } label: {
                ReadingActivityCard(
                    stats: stats,
                    palette: .amber,
                    morphNamespace: readingStatsNamespace,
                    morphID: readingStatsMorphID
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func audiobookGridItem(_ audiobook: Audiobook) -> some View {
        NavigationLink {
            AudiobookDetailView(audiobook: audiobook) {
                openPlayer()
            }
        } label: {
            AudiobookCardView(
                audiobook: audiobook,
                isCurrentlyPlaying: player.currentAudiobook?.id == audiobook.id,
                isLoadingPlayback: player.isLoadingPlayback(for: audiobook),
                downloadEntry: audiobook.catalogId.flatMap(downloadManager.entry(for:))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Resume", systemImage: "play.fill") {
                if audiobook.isStreamingOnly {
                    openPlayer()
                }
                Task {
                    await player.startPlayback(for: audiobook)
                    if !audiobook.isStreamingOnly {
                        try? await Task.sleep(for: .milliseconds(600))
                        openPlayer()
                    }
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
                Label(audiobook.isStreamingOnly ? "Remove from Library" : audiobook.isFreeBook ? "Remove Download" : "Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Player Presentation

    private func openPlayer() {
        isClosingPlayer = false
        if !isPlayerVisible {
            playerYOffset = screenHeight
            isPlayerVisible = true
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            playerYOffset = 0
        }
    }

    private func closePlayer() {
        guard !isClosingPlayer else { return }
        isClosingPlayer = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            playerYOffset = screenHeight
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            isPlayerVisible = false
            isClosingPlayer = false
        }
    }

    private func handlePlayerDragChanged(_ dragUp: CGFloat) {
        guard !isClosingPlayer else { return }
        if !isPlayerVisible && dragUp > 0 {
            playerYOffset = screenHeight
            isPlayerVisible = true
        }
        if isPlayerVisible {
            playerYOffset = max(0, screenHeight - dragUp)
        }
    }

    private func handlePlayerDragEnded(_ dragUp: CGFloat, velocity: CGFloat) {
        guard !isClosingPlayer else { return }
        if dragUp > screenHeight * 0.3 || velocity > 600 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                playerYOffset = 0
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                playerYOffset = screenHeight
            }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                isPlayerVisible = false
            }
        }
    }

    private func handlePlayerDismissDragChanged(_ dragDown: CGFloat) {
        guard isPlayerVisible, !isClosingPlayer else { return }
        playerYOffset = max(0, dragDown)
    }

    private func handlePlayerDismissDragEnded(_ dragDown: CGFloat, velocity: CGFloat) {
        guard isPlayerVisible, !isClosingPlayer else { return }
        let shouldDismiss = dragDown > screenHeight * 0.18 || velocity > 900

        if shouldDismiss {
            closePlayer()
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                playerYOffset = 0
            }
        }
    }

    // MARK: - Computed

    private func displayedBooks(for tab: LibraryTab) -> [Audiobook] {
        // Owned books synced from iCloud may exist without their audio on this device.
        // Hide those from the main grid — they only surface in Cloud Library for manual restore.
        // Free books stay visible: they keep remote URLs after sync and remain streamable.
        // Archived free books stay hidden unless this Library page is actively restoring that
        // exact row; Cloud Library remains their normal home.
        let base = audiobooks.filter { audiobook in
            LibraryBookVisibility.includes(
                bookID: audiobook.id,
                isDownloaded: audiobook.isDownloaded,
                isFreeBook: audiobook.isFreeBook,
                isArchived: audiobook.isArchived,
                isFavorite: audiobook.isFavorite,
                tab: tab,
                downloadEntry: audiobook.catalogId.flatMap(downloadManager.entry(for:))
            )
        }
        let sortRaw: String
        if tab == .favorites {
            sortRaw = favoritesSortRaw
        } else {
            sortRaw = allBooksSortRaw
        }
        return viewModel.sorted(base, by: sortRaw)
    }

    private var deleteAlertTitle: String {
        if viewModel.deleteCandidate?.isStreamingOnly == true {
            return "Remove from Library?"
        } else if viewModel.deleteCandidate?.isFreeBook == true {
            return "Remove Download?"
        } else if IcloudSyncGate.isEnabled() {
            return "Remove from this iPhone?"
        } else {
            return "Remove Audiobook?"
        }
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
    private func emptyState(for tab: LibraryTab) -> some View {
        if tab == .favorites {
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
                .foregroundStyle(Color(UIColor.systemBackground))

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
