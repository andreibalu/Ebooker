//
//  BrowseLibriVoxView.swift
//  Pageless
//

import SwiftUI

struct BrowseLibriVoxView: View {
    let onOpenPlayer: () -> Void
    let viewModel: BrowseLibriVoxViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var vm = viewModel
        ZStack {
            VStack(spacing: 0) {
                searchBar(vm: $vm.searchQuery)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                filterChipsRow

                syncBanner
                    .padding(.horizontal, 20)

                Divider()
                    .padding(.horizontal, 20)

                if !viewModel.activeDownloads.isEmpty {
                    activeDownloadsSection
                }

                contentArea
            }
            .background(Color.cream.ignoresSafeArea())

            if viewModel.isInitialLoading {
                firstLoadOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isInitialLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.featuredBooks.count)
        .onAppear {
            viewModel.triggerSyncIfNeeded(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.triggerSyncIfNeeded(modelContext: modelContext)
            }
        }
    }

    // MARK: - Active downloads pinned section

    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            VStack(spacing: 8) {
                ForEach(viewModel.sortedActiveDownloads) { download in
                    NavigationLink {
                        LibriVoxBookDetailView(book: download.book, onOpenPlayer: onOpenPlayer, browseViewModel: viewModel)
                    } label: {
                        activeDownloadCard(download)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 20)
        }
    }

    private func activeDownloadCard(_ download: ActiveLibriVoxDownload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.book.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(download.book.authorDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(remainingSizeLabel(for: download))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    viewModel.cancelDownload(bookId: download.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
            }
            ProgressView(value: download.progress)
                .tint(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func remainingSizeLabel(for download: ActiveLibriVoxDownload) -> String {
        let totalMB = download.book.estimatedDownloadSizeMB
        guard totalMB > 0 else { return "" }
        let remaining = max(0, Int((Double(totalMB) * (1.0 - download.progress)).rounded()))
        return "\(remaining) MB left"
    }

    // MARK: - First-load overlay

    private var firstLoadOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.primary)

                VStack(spacing: 6) {
                    Text(viewModel.isPreloadingFeatured ? "Finding Classics" : "Building Your Free Library")
                        .font(.headline)

                    Text(viewModel.isPreloadingFeatured
                         ? "Loading a handful of timeless audiobooks to get you started"
                         : "Downloading the catalog of 20,000+ public-domain audiobooks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
            .padding(.horizontal, 48)
        }
    }

    // MARK: - Filter dropdowns

    private var filterChipsRow: some View {
        HStack(spacing: 8) {
            if !viewModel.availableLanguages.isEmpty {
                Menu {
                    Button("All Languages") {
                        viewModel.selectedLanguage = nil
                        viewModel.triggerSearch(modelContext: modelContext)
                    }
                    Divider()
                    ForEach(viewModel.availableLanguages, id: \.self) { lang in
                        Button {
                            viewModel.selectedLanguage = viewModel.selectedLanguage == lang ? nil : lang
                            viewModel.triggerSearch(modelContext: modelContext)
                        } label: {
                            if viewModel.selectedLanguage == lang {
                                Label(lang, systemImage: "checkmark")
                            } else {
                                Text(lang)
                            }
                        }
                    }
                } label: {
                    filterDropdownLabel(viewModel.selectedLanguage ?? "Language", isSelected: viewModel.selectedLanguage != nil)
                }
            }

            if !viewModel.availableGenres.isEmpty {
                Menu {
                    Button("All Genres") {
                        viewModel.selectedGenre = nil
                        viewModel.triggerSearch(modelContext: modelContext)
                    }
                    Divider()
                    ForEach(viewModel.availableGenres, id: \.self) { genre in
                        Button {
                            viewModel.selectedGenre = viewModel.selectedGenre == genre ? nil : genre
                            viewModel.triggerSearch(modelContext: modelContext)
                        } label: {
                            if viewModel.selectedGenre == genre {
                                Label(genre, systemImage: "checkmark")
                            } else {
                                Text(genre)
                            }
                        }
                    }
                } label: {
                    filterDropdownLabel(viewModel.selectedGenre ?? "Genre", isSelected: viewModel.selectedGenre != nil)
                }
            }

            Menu {
                Button("Any Length") {
                    viewModel.selectedDuration = nil
                    viewModel.triggerSearch(modelContext: modelContext)
                }
                Divider()
                ForEach(DurationFilter.allCases) { dur in
                    Button {
                        viewModel.selectedDuration = viewModel.selectedDuration == dur ? nil : dur
                        viewModel.triggerSearch(modelContext: modelContext)
                    } label: {
                        if viewModel.selectedDuration == dur {
                            Label(dur.rawValue, systemImage: "checkmark")
                        } else {
                            Text(dur.rawValue)
                        }
                    }
                }
            } label: {
                filterDropdownLabel(viewModel.selectedDuration?.rawValue ?? "Length", isSelected: viewModel.selectedDuration != nil)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func filterDropdownLabel(_ text: String, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(isSelected ? .semibold : .regular))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.primary : Color.cardWhite,
            in: Capsule()
        )
        .foregroundStyle(isSelected ? Color.cream : Color.primary)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    // MARK: - Search bar

    private func searchBar(vm: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("Search 20,000+ free audiobooks", text: vm)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.searchQuery) { _, new in
                    viewModel.onQueryChanged(new, modelContext: modelContext)
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Sync banner

    @ViewBuilder
    private var syncBanner: some View {
        // Full catalog streaming in behind already-visible classics/cached data (non-blocking).
        if viewModel.isLoadingFullCatalog, case .syncing(let fetched) = viewModel.syncState {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text(viewModel.isFirstFullSync
                     ? "Loading the full library… \(fetched.formatted()) books"
                     : "Refreshing catalog… \(fetched.formatted()) updated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)

        // Offline but catalog is cached — search still works
        } else if viewModel.isOfflineWithCachedData {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                Text("Offline — showing saved books")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { viewModel.forceRefresh(modelContext: modelContext) }
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 6)

        // Online error (not an offline / no-data situation). Suppressed when the full-screen
        // failed state is already showing it, to avoid doubling up.
        } else if case .failed(let message, false) = viewModel.syncState, !viewModel.loadFailedWithNoData {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { viewModel.forceRefresh(modelContext: modelContext) }
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 6)

        // Steady state: show last-sync timestamp
        } else if viewModel.catalogCount > 0 {
            if case .syncing = viewModel.syncState {
                EmptyView() // first-time overlay is showing; don't double-up
            } else {
                Text(viewModel.lastSyncDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isOfflineWithNoData {
            noInternetState
        } else if viewModel.loadFailedWithNoData {
            loadFailedState
        } else if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               && !viewModel.hasActiveFilters {
            if !viewModel.featuredBooks.isEmpty {
                featuredBooksList
            } else if viewModel.isInitialLoading {
                Spacer() // overlay is covering the screen; keep layout stable
            } else {
                emptySearch
            }
        } else if viewModel.searchResults.isEmpty {
            noResults
        } else {
            resultsList
        }
    }

    // MARK: - Featured Books

    private var featuredBooksList: some View {
        List {
            Section {
                ForEach(viewModel.featuredBooks) { book in
                    NavigationLink {
                        LibriVoxBookDetailView(book: book, onOpenPlayer: onOpenPlayer, browseViewModel: viewModel)
                    } label: {
                        LibriVoxBookRow(book: book, browseViewModel: viewModel)
                    }
                    .listRowBackground(Color.cardWhite)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            } header: {
                Text("Popular Classics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }

            librivoxAttribution
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private var noInternetState: some View {
        ContentUnavailableView {
            Label("No Internet Connection", systemImage: "wifi.slash")
        } description: {
            Text("Free Books needs a connection the first time to load audiobooks from LibriVox. Connect to Wi‑Fi or cellular and tap Retry.")
        } actions: {
            Button("Retry") {
                viewModel.forceRefresh(modelContext: modelContext)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var loadFailedState: some View {
        ContentUnavailableView {
            Label("Couldn’t Load Free Books", systemImage: "exclamationmark.icloud")
        } description: {
            Text(viewModel.failureMessage ?? "Something went wrong reaching LibriVox. Please try again in a moment.")
        } actions: {
            Button("Try Again") {
                viewModel.forceRefresh(modelContext: modelContext)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptySearch: some View {
        ContentUnavailableView {
            Label("Search LibriVox", systemImage: "magnifyingglass")
        } description: {
            Text("Search by title or author, or use the filters above to browse by language, genre, or length.")
        }
    }

    private var noResults: some View {
        ContentUnavailableView.search(text: viewModel.searchQuery)
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.searchResults) { book in
                NavigationLink {
                    LibriVoxBookDetailView(book: book, onOpenPlayer: onOpenPlayer, browseViewModel: viewModel)
                } label: {
                    LibriVoxBookRow(book: book, browseViewModel: viewModel)
                }
                .listRowBackground(Color.cardWhite)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }

            librivoxAttribution
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private var librivoxAttribution: some View {
        Text("Free books courtesy of [LibriVox](https://librivox.org) \u{2014} public domain audio recorded by volunteers.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}
