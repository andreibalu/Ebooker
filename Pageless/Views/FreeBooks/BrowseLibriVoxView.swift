//
//  BrowseLibriVoxView.swift
//  Pageless
//
//  "Open Shelf" editorial browse surface: search + small-caps filters up top,
//  a rotating Today's Pick hero, the collections rail, and a numbered classics
//  chart set directly on the cream background with hairline rules — no boxed
//  inset lists. Serif (New York) for titles/headlines, serif italic for authors
//  and status copy, small-caps eyebrows for section labels and metadata.

import SwiftUI

/// The page's entire type scale — four text sizes, nothing else. Every label on
/// this surface uses one of these so the editorial look never drifts into a
/// dozen near-identical sizes.
private enum FBType {
    static let eyebrow: CGFloat = 10   // small-caps section labels & metadata
    static let body: CGFloat = 12      // serif-italic authors, status copy, blurbs
    static let title: CGFloat = 15     // serif row titles, rank numbers, search text
    static let headline: CGFloat = 19  // hero title, overlay & empty-state headlines
}

/// Small-caps eyebrow label: SF, semibold, tracked, uppercased, tabular digits.
private struct FBEyebrow: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: FBType.eyebrow, weight: .semibold))
            .tracking(FBType.eyebrow * 0.12)
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

/// Thin circular spinner — black arc on a 10% track, matching the prototype's
/// custom spinner rather than the stock UIActivityIndicator.
private struct FBSpinner: View {
    var size: CGFloat = 22
    @State private var spinning = false

    var body: some View {
        let lineWidth = max(2, size * 0.1)
        Circle()
            .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 0.7).repeatForever(autoreverses: false), value: spinning)
            )
            .frame(width: size, height: size)
            .onAppear { spinning = true }
    }
}

struct BrowseLibriVoxView: View {
    let onOpenPlayer: () -> Void
    let viewModel: BrowseLibriVoxViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("freeBooksCollectionsHidden") private var collectionsHiddenStored = false
    /// Mirrors `collectionsHiddenStored` — @AppStorage writes don't participate in
    /// animation transactions, so the view animates this local state and persists separately.
    @State private var collectionsHidden = false

    private var isSearching: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.hasActiveFilters
    }

    private var hairlineColor: Color { Color.primary.opacity(0.18) }

    var body: some View {
        @Bindable var vm = viewModel
        ZStack {
            VStack(spacing: 0) {
                searchBar(vm: $vm.searchQuery)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                filterRow
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                statusLine

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
            collectionsHidden = collectionsHiddenStored
            viewModel.triggerSyncIfNeeded(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.triggerSyncIfNeeded(modelContext: modelContext)
            }
        }
    }

    // MARK: - Building blocks

    private var hairline: some View {
        Rectangle()
            .fill(hairlineColor)
            .frame(height: 0.5)
    }

    /// SF section title at the app's classic header size (semibold subheadline)
    /// followed by a hairline rule stretching to the right edge.
    private func sectionHeader(_ label: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            hairline
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Search bar

    private func searchBar(vm: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField(
                "",
                text: vm,
                prompt: Text("Search titles & authors…")
                    .font(.system(size: FBType.title, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
            )
            .font(.system(size: FBType.title, design: .serif))
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
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.cardWhite, in: Capsule())
        .overlay(Capsule().strokeBorder(hairlineColor, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
    }

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: 22) {
            Menu {
                Button("All Languages") {
                    viewModel.selectedLanguage = nil
                    viewModel.triggerSearch(modelContext: modelContext)
                }
                Divider()
                ForEach(viewModel.languageOptions, id: \.self) { lang in
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
                filterLabel(viewModel.selectedLanguage ?? "Language", isSelected: viewModel.selectedLanguage != nil)
            }

            Menu {
                Button("All Genres") {
                    viewModel.selectedGenre = nil
                    viewModel.triggerSearch(modelContext: modelContext)
                }
                Divider()
                ForEach(viewModel.genreOptions, id: \.self) { genre in
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
                filterLabel(viewModel.selectedGenre ?? "Genre", isSelected: viewModel.selectedGenre != nil)
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
                filterLabel(viewModel.selectedDuration?.rawValue ?? "Length", isSelected: viewModel.selectedDuration != nil)
            }

            Spacer()
        }
    }

    private func filterLabel(_ text: String, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .font(.system(size: FBType.eyebrow, weight: .semibold))
                .tracking(FBType.eyebrow * 0.12)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.primary)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.amber)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Status line (syncing / offline / error)

    @ViewBuilder
    private var statusLine: some View {
        // Full catalog streaming in behind already-visible classics/cached data (non-blocking).
        if viewModel.isLoadingFullCatalog, case .syncing(let fetched) = viewModel.syncState {
            HStack(spacing: 8) {
                FBSpinner(size: 12)
                Text(viewModel.isFirstFullSync
                     ? "Fetching the catalog… \(fetched.formatted()) of 20,000"
                     : "Refreshing catalog… \(fetched.formatted()) updated")
                    .font(.system(size: FBType.body, design: .serif))
                    .italic()
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

        // Offline but catalog is cached — search still works
        } else if viewModel.isOfflineWithCachedData {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.amber)
                Text("Offline — showing saved books.")
                    .font(.system(size: FBType.body, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                Spacer()
                retryButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

        // Online error (not an offline / no-data situation). Suppressed when the full-screen
        // failed state is already showing it, to avoid doubling up.
        } else if case .failed(let message, false) = viewModel.syncState, !viewModel.loadFailedWithNoData {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.amber)
                Text(message)
                    .font(.system(size: FBType.body, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                retryButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var retryButton: some View {
        Button {
            viewModel.forceRefresh(modelContext: modelContext)
        } label: {
            Text("RETRY")
                .font(.system(size: FBType.eyebrow, weight: .semibold))
                .tracking(FBType.eyebrow * 0.12)
                .foregroundStyle(.primary)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(height: 1)
                        .offset(y: 2)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - First-load overlay

    private var firstLoadOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.cream.opacity(0.6))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                FBSpinner(size: 28)

                VStack(spacing: 8) {
                    Text(viewModel.isPreloadingFeatured ? "Finding the classics." : "Building your free library.")
                        .font(.system(size: FBType.headline, weight: .medium, design: .serif))

                    Text(viewModel.isPreloadingFeatured
                         ? "A handful of timeless audiobooks, on their way to you."
                         : "Fetching the catalog of 20,000+ public-domain recordings.")
                        .font(.system(size: FBType.body, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 34)
            .padding(.horizontal, 30)
            .frame(maxWidth: 300)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 14)
            .padding(.horizontal, 44)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isOfflineWithNoData {
            noInternetState
        } else if viewModel.loadFailedWithNoData {
            loadFailedState
        } else if !isSearching {
            if !viewModel.featuredBooks.isEmpty {
                browseContent
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

    // MARK: - Browse content (hero, collections, chart)

    /// Plain ScrollView rather than List: List can't animate row-height changes (the
    /// collapse snapped) and enforces a minimum row height that left a dead gap under
    /// the collapsed rail. In a VStack the conditional rail collapses smoothly.
    private var browseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !viewModel.activeDownloads.isEmpty {
                    downloadsSection
                }

                if let pick = viewModel.todaysPick {
                    heroCard(pick)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }

                collectionsHeaderButton
                    .padding(.top, 22)

                if !collectionsHidden {
                    collectionsRail
                        .transition(.opacity)
                }

                sectionHeader("Popular Classics")
                    .padding(.top, collectionsHidden ? 16 : 20)

                VStack(spacing: 0) {
                    let chart = viewModel.chartBooks
                    ForEach(Array(chart.enumerated()), id: \.element.id) { index, book in
                        chartRow(book, index: index, isLast: index == chart.count - 1)
                    }
                }
                .padding(.top, 2)

                colophon
            }
            .animation(.easeInOut(duration: 0.32), value: collectionsHidden)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Today's Pick hero

    private func heroCard(_ book: LibriVoxBook) -> some View {
        NavigationLink {
            LibriVoxBookDetailView(book: book, onOpenPlayer: onOpenPlayer, browseViewModel: viewModel)
        } label: {
            HStack(spacing: 16) {
                GeneratedCoverView(title: book.title)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .rotationEffect(.degrees(-2.5))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 6)

                VStack(alignment: .leading, spacing: 5) {
                    FBEyebrow(text: "Today's Pick · \(book.formattedDuration)", color: .amber)

                    Text(book.title)
                        .font(.system(size: FBType.headline, weight: .medium, design: .serif))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text("by \(book.authorDisplay)")
                        .font(.system(size: FBType.body, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    let blurb = BookDescriptionFormatting.plainText(fromHTMLFragment: book.bookDescription)
                    if !blurb.isEmpty {
                        Text(blurb)
                            .font(.system(size: FBType.body))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 7, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collections shelf

    private var collectionsHeaderButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.32)) {
                collectionsHidden.toggle()
            }
            collectionsHiddenStored = collectionsHidden
        } label: {
            HStack(spacing: 10) {
                Text("Collections")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collectionsHidden ? -90 : 0))
                hairline
            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var collectionsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(LibriVoxCollection.all) { collection in
                    NavigationLink {
                        LibriVoxCollectionView(
                            collection: collection,
                            onOpenPlayer: onOpenPlayer,
                            browseViewModel: viewModel
                        )
                    } label: {
                        collectionCard(collection)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
    }

    private func collectionCard(_ collection: LibriVoxCollection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: collection.iconSystemName)
                .font(.title3)
                .foregroundStyle(Color.amber)
                .frame(height: 24)
            Text(collection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(collection.bookIDs.count) books")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 132, height: 68, alignment: .topLeading)
        .padding(14)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Numbered chart row

    private func chartRow(_ book: LibriVoxBook, index: Int, isLast: Bool) -> some View {
        NavigationLink {
            LibriVoxBookDetailView(book: book, onOpenPlayer: onOpenPlayer, browseViewModel: viewModel)
        } label: {
            HStack(spacing: 13) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: FBType.title, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)

                GeneratedCoverView(title: book.title)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: FBType.title, weight: .medium, design: .serif))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(book.authorDisplay)
                        .font(.system(size: FBType.body, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    FBEyebrow(text: chartMeta(book), color: Color(.tertiaryLabel))
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LibriVoxSampleButton(book: book, browseViewModel: viewModel, size: 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { hairline }
        }
    }

    private func chartMeta(_ book: LibriVoxBook) -> String {
        guard book.totalTimeSecs > 0 else { return "Unknown length" }
        return "\(book.formattedDuration) · \(book.estimatedDownloadSizeMB) MB"
    }

    // MARK: - Active downloads (pinned above the hero)

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Downloading · \(viewModel.activeDownloads.count)")

            VStack(spacing: 0) {
                let downloads = viewModel.sortedActiveDownloads
                ForEach(downloads) { download in
                    downloadRow(download, isLast: download.id == downloads.last?.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .padding(.top, 14)
    }

    private func downloadRow(_ download: ActiveLibriVoxDownload, isLast: Bool) -> some View {
        NavigationLink {
            LibriVoxBookDetailView(book: download.book, onOpenPlayer: onOpenPlayer, browseViewModel: viewModel)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(download.book.title)
                        .font(.system(size: FBType.title, weight: .medium, design: .serif))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    FBEyebrow(text: remainingSizeLabel(for: download))

                    Button {
                        viewModel.cancelDownload(bookId: download.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(Color.amber)
                            .frame(width: geo.size.width * download.progress)
                    }
                }
                .frame(height: 2)
                .animation(.linear(duration: 0.2), value: download.progress)
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { hairline }
        }
    }

    private func remainingSizeLabel(for download: ActiveLibriVoxDownload) -> String {
        let totalMB = download.book.estimatedDownloadSizeMB
        guard totalMB > 0 else { return "" }
        let remaining = max(0, Int((Double(totalMB) * (1.0 - download.progress)).rounded()))
        return "\(remaining) MB left"
    }

    // MARK: - Search & filter results

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(foundLabel)
                    .padding(.top, 16)

                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, book in
                        chartRow(book, index: index, isLast: index == viewModel.searchResults.count - 1)
                    }
                }
                .padding(.top, 2)

                colophon
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var foundLabel: String {
        let n = viewModel.searchResults.count
        return "Found · \(n) Recording\(n == 1 ? "" : "s")"
    }

    private var noResults: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Nothing on this shelf.")
                .font(.system(size: FBType.headline, weight: .medium, design: .serif))
                .padding(.top, 14)
            Text("Try a different title or author, or clear a filter.")
                .font(.system(size: FBType.body, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty / error states

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

    // MARK: - Colophon

    private var colophon: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.primary.opacity(0.25))
                .frame(width: 28, height: 0.5)

            Text("Every book here is read by [LibriVox](https://librivox.org) volunteers and free in the public domain — yours to keep, forever.")
                .font(.system(size: FBType.body, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .tint(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 14)
    }
}
