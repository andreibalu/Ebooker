import SwiftData
import SwiftUI

struct MomentSearchView: View {
    let onOpenPlayer: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Moment.createdAt, order: .reverse) private var moments: [Moment]
    @State private var query = ""
    @State private var network = NetworkMonitor.shared
    @FocusState private var searchFocused: Bool

    private var results: [Moment] {
        let words = MomentSearch.words(query)
        if words.isEmpty { return Array(moments.filter { $0.audiobook != nil }.prefix(30)) }
        return moments.compactMap { moment -> (Moment, Int)? in
            MomentSearch.score(moment, words: words).map { (moment, $0) }
        }.sorted {
            $0.1 == $1.1 ? $0.0.createdAt > $1.0.createdAt : $0.1 > $1.1
        }.map { $0.0 }
    }

    /// Ranked results grouped by book in one pass, books in order of their best result.
    private func grouped(_ results: [Moment]) -> [(book: Audiobook, moments: [Moment])] {
        var groups: [(book: Audiobook, moments: [Moment])] = []
        var indexByBook: [UUID: Int] = [:]
        for moment in results {
            guard let book = moment.audiobook else { continue }
            if let index = indexByBook[book.id] {
                groups[index].moments.append(moment)
            } else {
                indexByBook[book.id] = groups.count
                groups.append((book, [moment]))
            }
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let results = self.results
                LazyVStack(alignment: .leading, spacing: 16) {
                    if results.isEmpty {
                        ContentUnavailableView(
                            moments.isEmpty ? "No Saved Moments" : "No Matching Moments",
                            systemImage: "magnifyingglass",
                            description: Text(moments.isEmpty
                                ? "Save a moment while listening to find it here across all your books."
                                : "Try another name, quote, character, or book.")
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(moments.isEmpty ? "momentSearch.empty" : "momentSearch.noResults")
                    } else {
                        if MomentSearch.words(query).isEmpty {
                            Text("Recent Moments").font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("momentSearch.recent")
                        }
                        ForEach(grouped(results), id: \.book.id) { book, bookMoments in
                            HStack(spacing: 10) {
                                cover(book).frame(width: 40, height: 48).clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading) {
                                    Text(MomentSearch.highlighted(book.title, query: query)).font(.headline)
                                    if !book.author.isEmpty {
                                        Text(MomentSearch.highlighted(book.author, query: query)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            ForEach(bookMoments) { moment in
                                MomentRow(audiobook: book, moment: moment, openPlayer: onOpenPlayer,
                                          onDelete: {}, searchQuery: query,
                                          unavailableReason: unavailableReason(book, moment: moment))
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Color.cream.ignoresSafeArea())
            .navigationTitle("Search Moments")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search saved moments")
            .searchFocused($searchFocused)
            .task { searchFocused = true }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("momentSearch.done")
                }
            }
        }
    }

    private func unavailableReason(_ book: Audiobook, moment: Moment) -> String? {
        if book.isArchived { return "Book has been removed from the library" }
        if book.isCloudOnlyOrphan { return "Audio is not on this iPhone" }
        if !book.sortedTracks.indices.contains(moment.trackIndex) { return "Track unavailable" }
        // Synced rows can claim local audio before orphan detection checks this device's files.
        if book.isDownloaded {
            let file = try? LibraryImportService.fileURL(for: book.sortedTracks[moment.trackIndex], in: book)
            if !(file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) {
                return "Audio is not on this iPhone"
            }
        }
        if book.isStreamingOnly && !network.isConnected { return "Connect to the internet to stream" }
        if book.isStreamingOnly && book.isAudiobookshelfBook {
            guard let server = ABSAccount.shared.summary?.baseURL else { return "Connect your Audiobookshelf server to play" }
            let stored = book.sortedTracks[moment.trackIndex].remoteURLString ?? ""
            if !AudiobookshelfClient.isSameOrigin(stored, base: server) { return "Connect to this book's Audiobookshelf server" }
        }
        return nil
    }

    @ViewBuilder
    private func cover(_ book: Audiobook) -> some View {
        if let data = book.coverArtData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            GeneratedCoverView(title: book.title)
        }
    }
}
