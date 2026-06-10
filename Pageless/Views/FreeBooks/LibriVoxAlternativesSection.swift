//
//  LibriVoxAlternativesSection.swift
//  Pageless
//

import SwiftUI
import SwiftData

/// "Other Recordings" — alternative LibriVox recordings of the same text (same
/// author + language, normalized title), resolved from the local catalog cache.
/// Shared by the catalog detail page and the library detail page for free books.
/// Renders nothing when no alternatives exist.
struct LibriVoxAlternativesSection: View {
    let book: LibriVoxBook
    let onOpenPlayer: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var alternatives: [LibriVoxBook] = []
    /// Memoized first-track URLs for inline samples; deliberately independent of
    /// `BrowseLibriVoxViewModel` so the section also works from the library detail page.
    @State private var firstTrackURLs: [String: URL] = [:]

    var body: some View {
        content
            .task(id: book.id) {
                alternatives = LibriVoxAlternativesFinder.alternatives(to: book, context: modelContext)
            }
    }

    /// The empty branch must still render *something* (a zero-height anchor) —
    /// a structurally absent view never appears, so `.task` would never fire
    /// and the alternatives could never load.
    @ViewBuilder
    private var content: some View {
        if alternatives.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Other Recordings")
                        .font(.headline)
                    Text("\(alternatives.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Same book, different narrators. Play a sample to compare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(alternatives) { alternative in
                        row(for: alternative)
                        if alternative.id != alternatives.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func row(for alternative: LibriVoxBook) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                LibriVoxBookDetailView(book: alternative, onOpenPlayer: onOpenPlayer)
            } label: {
                HStack(spacing: 12) {
                    GeneratedCoverView(title: alternative.title)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LibriVoxAlternativesFinder.versionLabel(alternative.title) ?? "Original")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(alternative.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            sampleButton(for: alternative)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Sample

    private func sampleButton(for alternative: LibriVoxBook) -> some View {
        Button {
            if SamplePlayer.shared.isActive(for: alternative.id) {
                SamplePlayer.shared.stop()
            } else {
                Task {
                    if let url = await fetchFirstTrackURL(for: alternative) {
                        SamplePlayer.shared.playSample(bookId: alternative.id, trackURL: url)
                    }
                }
            }
        } label: {
            Group {
                if case .loading(let id) = SamplePlayer.shared.state, id == alternative.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: SamplePlayer.shared.isActive(for: alternative.id) ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(SamplePlayer.shared.isActive(for: alternative.id) ? .red : .primary)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(!NetworkMonitor.shared.isConnected && !SamplePlayer.shared.isActive(for: alternative.id))
    }

    /// Same resolution order as `BrowseLibriVoxViewModel.fetchFirstTrackURL`:
    /// cached tracks on the book first, then the audiotracks feed.
    private func fetchFirstTrackURL(for book: LibriVoxBook) async -> URL? {
        if let cached = firstTrackURLs[book.id] { return cached }
        if let cachedTracks = book.cachedTracks, let first = cachedTracks.first,
           let url = URL(string: first.listenURL) {
            firstTrackURLs[book.id] = url
            return url
        }
        guard let tracks = try? await LibriVoxAPIClient.fetchTracks(projectID: book.id),
              let first = tracks.first,
              let url = URL(string: first.listenURL) else { return nil }
        firstTrackURLs[book.id] = url
        return url
    }
}
