import SwiftData
import SwiftUI

@MainActor
enum MomentSearch {
    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func score(_ moment: Moment, words: [String]) -> Int? {
        guard let book = moment.audiobook else { return nil }
        let titles = fold([moment.label, book.title, book.author].joined(separator: " "))
        let prose = fold([moment.notes ?? "", moment.quoteLine ?? ""].joined(separator: " "))
        let metadata = fold((moment.characters + moment.categories.map(\.displayName)
                            + [moment.mood?.displayName].compactMap { $0 }).joined(separator: " "))
        guard words.allSatisfy({ titles.contains($0) || prose.contains($0) || metadata.contains($0) }) else { return nil }
        return words.reduce(0) { $0 + (titles.contains($1) ? 10 : prose.contains($1) ? 2 : 0) }
    }

    static func highlighted(_ value: String, query: String) -> AttributedString {
        var result = AttributedString(value)
        for word in words(query) {
            var start = value.startIndex
            while start < value.endIndex,
                  let range = value.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                          range: start..<value.endIndex, locale: .current) {
                if let lower = AttributedString.Index(range.lowerBound, within: result),
                   let upper = AttributedString.Index(range.upperBound, within: result) {
                    result[lower..<upper].backgroundColor = Color.amber.opacity(0.25)
                }
                start = range.upperBound
            }
        }
        return result
    }
}

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

    private var books: [Audiobook] {
        var seen = Set<UUID>()
        return results.compactMap(\.audiobook).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                        ForEach(books) { book in
                            HStack(spacing: 10) {
                                cover(book).frame(width: 40, height: 48).clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading) {
                                    Text(MomentSearch.highlighted(book.title, query: query)).font(.headline)
                                    if !book.author.isEmpty {
                                        Text(MomentSearch.highlighted(book.author, query: query)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            ForEach(results.filter { $0.audiobook?.id == book.id }) { moment in
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
        if book.isStreamingOnly && !network.isConnected { return "Connect to the internet to stream" }
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
