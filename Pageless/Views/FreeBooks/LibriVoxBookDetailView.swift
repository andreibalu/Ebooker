//
//  LibriVoxBookDetailView.swift
//  Pageless
//

import SwiftData
import SwiftUI

struct LibriVoxBookDetailView: View {
    let book: LibriVoxBook
    let onOpenPlayer: () -> Void
    let browseViewModel: BrowseLibriVoxViewModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(LibriVoxDownloadManager.self) private var downloadManager
    @State private var viewModel = LibriVoxBookDetailViewModel()
    @State private var descriptionExpanded = false
    @State private var sampleTrackURL: URL?

    private enum DownloadActionContainerState: Equatable {
        case ready
        case active
        case downloaded
    }

    private var downloadActionContainerState: DownloadActionContainerState {
        if downloadManager.entry(for: book.id) != nil {
            return .active
        }
        return viewModel.isDownloaded ? .downloaded : .ready
    }

    init(book: LibriVoxBook, onOpenPlayer: @escaping () -> Void, browseViewModel: BrowseLibriVoxViewModel? = nil) {
        self.book = book
        self.onOpenPlayer = onOpenPlayer
        self.browseViewModel = browseViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                sampleSection
                descriptionSection
                Group {
                    actionSection
                        .id(downloadActionContainerState)
                        .transition(AppMotion.stateTransition(reduceMotion: reduceMotion))
                }
                .animation(
                    AppMotion.stateChangeAnimation(reduceMotion: reduceMotion),
                    value: downloadActionContainerState
                )
                completionSection
                LibriVoxAlternativesSection(book: book, onOpenPlayer: onOpenPlayer)
            }
            .padding(20)
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.refreshIdentity(book: book, modelContext: modelContext)
            }
        }
        .task(id: book.id) {
            if let browseViewModel {
                await browseViewModel.refreshBookIfStale(book, modelContext: modelContext)
            } else if Date.now.timeIntervalSince(book.lastSyncedAt) >= 86_400,
                      let refreshed = try? await LibriVoxAPIClient.fetchBook(id: book.id) {
                try? LibriVoxCatalogSync.seed([refreshed], into: modelContext)
            }
        }
        .onChange(of: downloadManager.entry(for: book.id)?.phase) { _, _ in
            viewModel.refreshIdentity(book: book, modelContext: modelContext)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            coverArt
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.authorDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if book.totalTimeSecs > 0 {
                    Label(book.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Label("\(book.estimatedDownloadSizeMB) MB", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if !book.language.isEmpty {
                    Label(book.language, systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var coverArt: some View {
        GeneratedCoverView(title: book.title)
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    // MARK: - Description

    @ViewBuilder
    private var descriptionSection: some View {
        let text = BookDescriptionFormatting.plainText(fromHTMLFragment: book.bookDescription)
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionExpanded ? nil : 4)
                    .animation(.easeInOut(duration: 0.2), value: descriptionExpanded)
                Button(descriptionExpanded ? "Show less" : "Show more") {
                    descriptionExpanded.toggle()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Sample

    private var sampleSection: some View {
        Button {
            if SamplePlayer.shared.isActive(for: book.id) {
                SamplePlayer.shared.stop()
            } else {
                SamplePlayer.shared.beginLoading(bookId: book.id)
                Task {
                    guard let url = await fetchSampleURL() else {
                        SamplePlayer.shared.stop()
                        return
                    }
                    guard SamplePlayer.shared.isActive(for: book.id) else { return }
                    SamplePlayer.shared.playSample(bookId: book.id, trackURL: url)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Group {
                    if case .loading(let id) = SamplePlayer.shared.state, id == book.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: SamplePlayer.shared.isActive(for: book.id) ? "stop.fill" : "play.fill")
                    }
                }
                .frame(width: 16)
                Text(SamplePlayer.shared.isActive(for: book.id) ? "Stop Sample" : "Play \(SamplePlayer.sampleDurationSeconds)s Sample")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!NetworkMonitor.shared.isConnected && !SamplePlayer.shared.isActive(for: book.id))
    }

    /// Resolves the first track URL without requiring a `browseViewModel` —
    /// this view is also pushed from the alternatives section, which has none.
    /// Same resolution order as `BrowseLibriVoxViewModel.fetchFirstTrackURL`:
    /// cached tracks on the book first, then the audiotracks feed.
    private func fetchSampleURL() async -> URL? {
        if let sampleTrackURL { return sampleTrackURL }
        if let browseViewModel, let url = await browseViewModel.fetchFirstTrackURL(for: book) {
            sampleTrackURL = url
            return url
        }
        if let cachedTracks = book.cachedTracks, let first = cachedTracks.first,
           let url = URL(string: first.listenURL) {
            sampleTrackURL = url
            return url
        }
        guard let tracks = try? await LibriVoxAPIClient.fetchTracks(projectID: book.id),
              let first = tracks.first,
              let url = URL(string: first.listenURL) else { return nil }
        sampleTrackURL = url
        return url
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionSection: some View {
        if let entry = downloadManager.entry(for: book.id) {
            downloadStatus(entry)
        } else if viewModel.isDownloaded {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let message = viewModel.requestErrorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                Button {
                    viewModel.startDownload(
                        book: book,
                        modelContext: modelContext,
                        manager: downloadManager
                    )
                } label: {
                    Label("Download Free Book", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .controlSize(.large)

                if !viewModel.isActiveInLibrary {
                    addToLibraryButton
                }
            }
        }
    }

    @ViewBuilder
    private func downloadStatus(_ entry: LibriVoxDownloadManager.Entry) -> some View {
        LibriVoxDetailDownloadStatus(entry: entry, progressTint: .primary)
    }

    // MARK: - Add to Library

    @ViewBuilder
    private var addToLibraryButton: some View {
        switch viewModel.addToLibraryState {
        case .idle:
            Button {
                Task {
                    await viewModel.addToLibrary(book: book, modelContext: modelContext)
                }
            } label: {
                Label("Add to Library", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Adding to library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .complete:
            EmptyView()

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Try Again") {
                    Task {
                        await viewModel.addToLibrary(book: book, modelContext: modelContext)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Completion

    @ViewBuilder
    private var completionSection: some View {
        let completedAudiobook: Audiobook? = {
            if case .complete(let ab) = viewModel.addToLibraryState { return ab }
            if viewModel.isActiveInLibrary { return viewModel.libraryAudiobook }
            return nil
        }()

        if let audiobook = completedAudiobook {
            VStack(spacing: 12) {
                Label("Added to Your Library", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                NavigationLink {
                    AudiobookDetailView(audiobook: audiobook, openPlayer: onOpenPlayer)
                } label: {
                    Label("View in Library", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 4)
        }
    }
}
