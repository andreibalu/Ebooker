//
//  LibriVoxBookDetailView.swift
//  Pageless
//

import SwiftUI

struct LibriVoxBookDetailView: View {
    let book: LibriVoxBook
    let onOpenPlayer: () -> Void
    let browseViewModel: BrowseLibriVoxViewModel?

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LibriVoxBookDetailViewModel()
    @State private var descriptionExpanded = false

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
                actionSection
                completionSection
            }
            .padding(20)
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
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
        AsyncImage(url: book.bestCoverURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                Task {
                    if let url = await browseViewModel?.fetchFirstTrackURL(for: book) {
                        SamplePlayer.shared.playSample(bookId: book.id, trackURL: url)
                    }
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

    // MARK: - Actions

    @ViewBuilder
    private var actionSection: some View {
        if viewModel.isAlreadyInLibrary {
            EmptyView()
        } else if let trackerDownload = browseViewModel?.activeDownloads[book.id], !viewModel.downloadState.isActive {
            // Another session is already downloading this book
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading…")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(trackerDownload.completed) / \(trackerDownload.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: trackerDownload.progress)
                    .tint(.primary)
                Button("Cancel Download") {
                    browseViewModel?.cancelDownload(bookId: book.id)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } else {
            switch viewModel.downloadState {
            case .idle:
                VStack(spacing: 10) {
                    Button {
                        viewModel.startDownload(book: book, modelContext: modelContext, tracker: browseViewModel)
                    } label: {
                        Label("Download Free Book", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    addToLibraryButton
                }

            case .fetchingTracks:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Fetching track list…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Button("Cancel") {
                        viewModel.cancelDownload()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            case .downloading(let completed, let total):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloading…")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(completed) / \(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completed), total: Double(max(total, 1)))
                        .tint(.primary)
                    Button("Cancel") {
                        viewModel.cancelDownload()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            case .complete:
                EmptyView()

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Button("Try Again") {
                        viewModel.startDownload(book: book, modelContext: modelContext, tracker: browseViewModel)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Add to Library

    @ViewBuilder
    private var addToLibraryButton: some View {
        switch viewModel.addToLibraryState {
        case .idle:
            Button {
                viewModel.addToLibrary(book: book, modelContext: modelContext)
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
                    viewModel.addToLibrary(book: book, modelContext: modelContext)
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
            if case .complete(let ab) = viewModel.downloadState { return ab }
            if case .complete(let ab) = viewModel.addToLibraryState { return ab }
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
