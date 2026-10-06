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
        case .freeBooks: "Shelves"
        }
    }

    static func order(startOnFreeBooks: Bool) -> [LibraryTab] {
        startOnFreeBooks ? [.favorites, .freeBooks, .allBooks] : [.favorites, .allBooks, .freeBooks]
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
        isAudiobookshelfBook: Bool = false,
        tab: LibraryTab,
        downloadEntry: LibriVoxDownloadManager.Entry?
    ) -> Bool {
        // Audiobookshelf books stream from the user's server, so like free books they are visible
        // without local files — they are never cloud-only orphans.
        let normallyVisible = (isDownloaded || isFreeBook || isAudiobookshelfBook) && !isArchived
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

    static func visibleCount(
        in books: [Audiobook],
        downloadEntry: (Audiobook) -> LibriVoxDownloadManager.Entry?
    ) -> Int {
        books.filter { book in
            includes(
                bookID: book.id,
                isDownloaded: book.isDownloaded,
                isFreeBook: book.isFreeBook,
                isArchived: book.isArchived,
                isFavorite: book.isFavorite,
                isAudiobookshelfBook: book.isAudiobookshelfBook,
                tab: .allBooks,
                downloadEntry: downloadEntry(book)
            )
        }.count
    }
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingManager.self) private var onboarding
    @Environment(LibriVoxDownloadManager.self) private var downloadManager
    @Environment(UnpagedRouter.self) private var router
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var plusEntitlementStore: PlusEntitlementStore
    @Query private var audiobooks: [Audiobook]
    @Query(sort: \ReadingSession.date, order: .reverse) private var readingSessions: [ReadingSession]
    @Namespace private var readingStatsNamespace
    private let readingStatsMorphID = "reading-activity-heatmap"

    // Each library tab keeps its own sort preference. "librarySortOption" remains the Library
    // key so existing users keep their saved choice; Favorites gets its own independent key.
    @AppStorage("librarySortOption") private var allBooksSortRaw = LibrarySortOption.recent.rawValue
    @AppStorage("favoritesSortOption") private var favoritesSortRaw = LibrarySortOption.recent.rawValue
    // When the user chose Shelves in onboarding, the app always opens there and the tabs reorder
    // to Favorites / Shelves / Library. Keep the existing key for returning users.
    @AppStorage("startOnFreeBooks") private var startOnFreeBooks = false
    @AppStorage(ShelvesSourcePreference.storageKey)
    private var storedShelvesSourceID = ShelvesSourcePreference.defaultSourceID
    @AppStorage("resumeBacktrackSeconds") private var resumeBacktrackSeconds = ResumeBacktrackOption.oneMinute.rawValue
    @AppStorage("skipBackSeconds") private var skipBackSeconds = SkipIntervalOption.thirty.rawValue
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = SkipIntervalOption.thirty.rawValue

    @State private var viewModel = LibraryViewModel()
    @State private var browseViewModel = BrowseLibriVoxViewModel()
    @State private var absAccount = ABSAccount.shared
    @State private var isABSConnectPresented = false
    @State private var selectedTab: LibraryTab = .favorites
    @State private var didApplyInitialTab = false
    @State private var isImporterPresented = false
    @State private var isPlayerVisible = false
    @State private var isClosingPlayer = false
    @State private var playerYOffset: CGFloat = UIScreen.main.bounds.height
    @State private var playerOpacity: Double = 0
    @State private var playerTeardownTask: Task<Void, Never>?
    @State private var playerDismissGeneration: UInt = 0
    @State private var isSettingsPresented = false
    @State private var isPlusHubPresented = false
    @State private var downloadScrollRequest = 0
    @State private var selectedLibraryDownloadBook: LibriVoxBook?
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
                    .navigationDestination(item: $selectedLibraryDownloadBook) { book in
                        LibriVoxBookDetailView(
                            book: book,
                            onOpenPlayer: openPlayer,
                            browseViewModel: browseViewModel
                        )
                    }
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
                    .environmentObject(plusEntitlementStore)
                    .offset(y: reduceMotion ? 0 : playerYOffset)
                    .opacity(playerOpacity)
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
            SettingsView(onOpenAudiobookshelf: openAudiobookshelfShelves)
            .environmentObject(plusEntitlementStore)
            .environment(onboarding)
        }
        .sheet(isPresented: $isABSConnectPresented) {
            ABSConnectView(account: absAccount) {
                storedShelvesSourceID = BookSourceRegistry.audiobookshelfID
                selectedTab = .freeBooks
            }
        }
        .sheet(isPresented: $isPlusHubPresented) {
            PlusHubView()
            .environmentObject(player)
            .environmentObject(plusEntitlementStore)
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
            if viewModel.deleteCandidate?.isAudiobookshelfBook == true {
                Button("Remove from Library", role: .destructive) {
                    if let book = viewModel.deleteCandidate {
                        viewModel.deleteAudiobookshelfBook(book, modelContext: modelContext)
                        viewModel.deleteCandidate = nil
                    }
                }
            } else if viewModel.deleteCandidate?.isStreamingOnly == true {
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
            if viewModel.deleteCandidate?.isAudiobookshelfBook == true {
                Text("Removes this book from Unpaged. It stays on your Audiobookshelf server, and you can add it again from Shelves.")
            } else if viewModel.deleteCandidate?.isStreamingOnly == true {
                if IcloudSyncGate.isEnabled() {
                    Text("Removes this book from your library on this iPhone. Your progress and bookmarks stay in your iCloud Library, and you can stream it again anytime.")
                } else {
                    Text("This will remove the book from your library. You can add it again from Shelves.")
                }
            } else if viewModel.deleteCandidate?.isFreeBook == true {
                if IcloudSyncGate.isEnabled() {
                    Text("Removes the download from this iPhone. Your progress and bookmarks stay in your iCloud Library, and you can stream or re-download it anytime.")
                } else {
                    Text("This will remove the downloaded audiobook. You can download it again from Shelves.")
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
                let book = viewModel.renameCandidate
                let previousTitle = book?.title
                viewModel.commitRename()
                do { try modelContext.save() }
                catch {
                    if let previousTitle { book?.title = previousTitle }
                    viewModel.presentAlert(title: "Could Not Rename Audiobook", message: error.localizedDescription)
                }
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
            storedShelvesSourceID = resolvedShelvesSourceID
            // One-time launch-tab application for relaunched users (first-run routing is handled by
            // the onboarding onFinish closure). Shelves choosers open there on every launch.
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
        .onDisappear {
            playerTeardownTask?.cancel()
            playerTeardownTask = nil
            playerDismissGeneration &+= 1
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
        .onChange(of: router.pendingRoute) { _, route in
            guard route == .downloads else { return }
            playerTeardownTask?.cancel()
            playerTeardownTask = nil
            playerDismissGeneration &+= 1
            isPlayerVisible = false
            isSettingsPresented = false
            isPlusHubPresented = false
            selectedTab = .allBooks
            downloadScrollRequest &+= 1
            router.consume(.downloads)
        }
    }

    // MARK: - Header

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 48, height: 48)
                Text("\(visibleLibraryBookCount)")
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
                // Unpaged Plus hub — always shown. It is the purchase entry point (keeps the iCloud
                // Sync purchase reachable without iCloud sign-in, Apple 3.1.1) and, for users whose
                // sync is on, holds the iCloud Library.
                Button {
                    isPlusHubPresented = true
                } label: {
                    toolbarIconButton(systemName: "sparkles")
                        .foregroundStyle(Color.amber)
                }
                .accessibilityLabel("Unpaged Plus")
                .accessibilityIdentifier("plusButton")

                Button {
                    isSettingsPresented = true
                } label: {
                    toolbarIconButton(systemName: "slider.horizontal.3")
                }
                .accessibilityIdentifier("settingsButton")

                Button {
                    #if DEBUG
                    if E2EFixtures.enabled,
                       ProcessInfo.processInfo.arguments.contains("-e2e-import") {
                        do {
                            viewModel.handleImportSelection(.success([try E2EFixtures.importSource()]),
                                                            modelContext: modelContext)
                        } catch {
                            viewModel.handleImportSelection(.failure(error), modelContext: modelContext)
                        }
                    } else {
                        isImporterPresented = true
                    }
                    #else
                    isImporterPresented = true
                    #endif
                } label: {
                    toolbarIconButton(systemName: "plus")
                }
                .accessibilityIdentifier("importButton")
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

    /// Tab order is fixed for own-book users (Favorites / Library / Shelves). Users who chose
    /// Shelves in onboarding get it promoted to the center (Favorites / Shelves / Library).
    private var tabOrder: [LibraryTab] {
        LibraryTab.order(startOnFreeBooks: startOnFreeBooks)
    }

    private var registeredBookSources: [BookSource] {
        // Read through the observed account so the menu and tab page update on connect/disconnect.
        BookSourceRegistry.sources(isAudiobookshelfConfigured: absAccount.isConnected)
    }

    /// Settings → Audiobookshelf → "Open in Shelves": close Settings and show the server's shelf.
    private func openAudiobookshelfShelves() {
        isSettingsPresented = false
        isPlusHubPresented = false
        if absAccount.isConnected {
            storedShelvesSourceID = BookSourceRegistry.audiobookshelfID
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = .freeBooks
        }
    }

    private var resolvedShelvesSourceID: String {
        ShelvesSourcePreference.resolvedSourceID(storedShelvesSourceID, from: registeredBookSources)
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
            sourceTabButton(title: tab.title, tab: .freeBooks)
        }
    }

    /// The Shelves tab mirrors `sortableTabButton`: tapping it while inactive switches to it,
    /// tapping it *while already active* drops a menu down from the title — here choosing which
    /// catalog the tab shows. Buttons rather than a `Picker` so an unconfigured source can be
    /// disabled and say so.
    @ViewBuilder
    private func sourceTabButton(title: String, tab: LibraryTab) -> some View {
        let isSelected = selectedTab == tab
        // With a single registered source the menu would be a one-item no-op, so the chevron and
        // the menu only appear once there is something to switch between.
        let offersChoice = isSelected && registeredBookSources.count > 1
        Group {
            if offersChoice {
                Menu {
                    Section("Catalog source") {
                        ForEach(registeredBookSources, id: \.id) { source in
                            Button {
                                if source.isConfigured {
                                    storedShelvesSourceID = source.id
                                } else if source.id == BookSourceRegistry.audiobookshelfID {
                                    // Unconfigured server source: choosing it starts setup.
                                    isABSConnectPresented = true
                                }
                            } label: {
                                if source.id == resolvedShelvesSourceID {
                                    Label(source.name, systemImage: "checkmark")
                                } else if source.isConfigured {
                                    Text(source.name)
                                } else {
                                    Text("\(source.name)")
                                    Text("Connect your server")
                                }
                            }
                            .accessibilityIdentifier("shelvesSource.\(source.id)")
                        }
                    }
                } label: {
                    tabColumn(title: title, isSelected: true, showsChevron: true)
                }
            } else {
                Button {
                    guard !isSelected else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    tabColumn(title: title, isSelected: isSelected, showsChevron: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("shelvesTab")
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
        .accessibilityIdentifier(tab == .favorites ? "favoritesTab" : "libraryTab")
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
            // `resolvedShelvesSourceID` always names a configured source (falling back to
            // LibriVox), so the tab is never blank. A second source branches here on that id.
            if resolvedShelvesSourceID == BookSourceRegistry.audiobookshelfID {
                ABSBrowseView(onOpenPlayer: openPlayer, account: absAccount)
            } else {
                BrowseLibriVoxView(onOpenPlayer: openPlayer, viewModel: browseViewModel)
            }
        }
    }

    @ViewBuilder
    private func booksGrid(for tab: LibraryTab) -> some View {
        let books = displayedBooks(for: tab)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if tab == .allBooks {
                        LibriVoxDownloadSection { catalogID in
                            selectedLibraryDownloadBook = browseViewModel.catalogBook(
                                id: catalogID,
                                modelContext: modelContext
                            )
                        }
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
            .onChange(of: downloadScrollRequest) { _, _ in
                guard tab == .allBooks else { return }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo("library-downloads", anchor: .top)
                }
            }
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
            .accessibilityIdentifier("readingActivity")
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
        .accessibilityIdentifier("book.card.\(audiobook.folderName)")
        .contextMenu {
            Button("Resume", systemImage: "play.fill") {
                if audiobook.isStreamingOnly {
                    openPlayer()
                }
                Task {
                    await player.startPlayback(for: audiobook)
                    if !audiobook.isStreamingOnly {
                        openPlayer()
                    }
                }
            }

            Button(audiobook.isFavorite ? "Unfavorite" : "Favorite", systemImage: audiobook.isFavorite ? "heart.slash" : "heart") {
                let previous = audiobook.isFavorite
                audiobook.isFavorite.toggle()
                do { try modelContext.save() }
                catch {
                    audiobook.isFavorite = previous
                    viewModel.presentAlert(title: "Could Not Save Favorite", message: error.localizedDescription)
                }
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
        playerTeardownTask?.cancel()
        playerTeardownTask = nil
        playerDismissGeneration &+= 1
        isClosingPlayer = false

        if reduceMotion {
            playerYOffset = 0
            if !isPlayerVisible {
                playerOpacity = 0
                isPlayerVisible = true
            }
            withAnimation(.easeOut(duration: 0.2)) {
                playerOpacity = 1
            }
        } else {
            playerOpacity = 1
            if !isPlayerVisible {
                playerYOffset = screenHeight
                isPlayerVisible = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                playerYOffset = 0
            }
        }
    }

    private func closePlayer() {
        guard !isClosingPlayer else { return }
        beginPlayerDismiss(response: 0.4, delay: .milliseconds(450))
    }

    private func beginPlayerDismiss(response: Double, delay: Duration) {
        playerTeardownTask?.cancel()
        playerTeardownTask = nil
        playerDismissGeneration &+= 1
        let generation = playerDismissGeneration
        isClosingPlayer = true

        if reduceMotion {
            playerYOffset = 0
            withAnimation(.easeOut(duration: 0.2)) {
                playerOpacity = 0
            }
        } else {
            withAnimation(.spring(response: response, dampingFraction: 0.85)) {
                playerYOffset = screenHeight
            }
        }

        playerTeardownTask = Task { @MainActor in
            try? await Task.sleep(for: reduceMotion ? .milliseconds(200) : delay)
            guard !Task.isCancelled, generation == playerDismissGeneration else { return }
            isPlayerVisible = false
            isClosingPlayer = false
            playerTeardownTask = nil
        }
    }

    private func handlePlayerDragChanged(_ dragUp: CGFloat) {
        guard !isClosingPlayer else { return }
        guard !reduceMotion else { return }
        if !isPlayerVisible && dragUp > 0 {
            playerYOffset = screenHeight
            isPlayerVisible = true
            playerOpacity = 1
        }
        if isPlayerVisible {
            playerYOffset = max(0, screenHeight - dragUp)
        }
    }

    private func handlePlayerDragEnded(_ dragUp: CGFloat, velocity: CGFloat) {
        guard !isClosingPlayer else { return }
        if dragUp > screenHeight * 0.3 || velocity > 600 {
            if reduceMotion {
                openPlayer()
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    playerYOffset = 0
                }
            }
        } else if reduceMotion {
            if isPlayerVisible {
                beginPlayerDismiss(response: 0.35, delay: .milliseconds(400))
            }
        } else {
            beginPlayerDismiss(response: 0.35, delay: .milliseconds(400))
        }
    }

    private func handlePlayerDismissDragChanged(_ dragDown: CGFloat) {
        guard isPlayerVisible, !isClosingPlayer else { return }
        guard !reduceMotion else { return }
        playerYOffset = max(0, dragDown)
    }

    private func handlePlayerDismissDragEnded(_ dragDown: CGFloat, velocity: CGFloat) {
        guard isPlayerVisible, !isClosingPlayer else { return }
        let shouldDismiss = dragDown > screenHeight * 0.18 || velocity > 900

        if shouldDismiss {
            closePlayer()
        } else if reduceMotion {
            openPlayer()
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                playerYOffset = 0
            }
        }
    }

    // MARK: - Computed

    private var visibleLibraryBookCount: Int {
        LibraryBookVisibility.visibleCount(in: audiobooks) { audiobook in
            audiobook.catalogId.flatMap(downloadManager.entry(for:))
        }
    }

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
                isAudiobookshelfBook: audiobook.isAudiobookshelfBook,
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

                Button("Browse Shelves") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .freeBooks
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
