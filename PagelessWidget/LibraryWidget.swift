//
//  LibraryWidget.swift
//  PagelessWidget
//

import SwiftUI
import WidgetKit

struct LibraryEntry: TimelineEntry {
    let date: Date
    let books: [SharedBookData]
}

struct LibraryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry {
        LibraryEntry(date: .now, books: SharedBookData.placeholders)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        let books = SharedDefaults.loadLibrary()
        completion(LibraryEntry(date: .now, books: books.isEmpty ? SharedBookData.placeholders : books))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        let books = SharedDefaults.loadLibrary()
        let entry = LibraryEntry(date: .now, books: books)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(600)))
        completion(timeline)
    }
}

struct LibraryWidgetEntryView: View {
    var entry: LibraryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.books.isEmpty {
            emptyView
        } else {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            default:
                mediumView
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let book = recentBook {
                bookRow(book)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .widgetURL(URL(string: "pageless://library"))
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Listening")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(recentBooks.prefix(2))) { book in
                Link(destination: URL(string: "pageless://book/\(book.id)")!) {
                    bookRow(book)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private func bookRow(_ book: SharedBookData) -> some View {
        HStack(spacing: 10) {
            if let coverData = book.coverArtData, let uiImage = UIImage(data: coverData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                ProgressView(value: book.progress)
                    .tint(.primary)

                Text("\(Int(book.progress * 100))% complete")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No Audiobooks")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .widgetURL(URL(string: "pageless://library"))
    }

    private var recentBook: SharedBookData? {
        recentBooks.first
    }

    private var recentBooks: [SharedBookData] {
        entry.books.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }
}

struct LibraryWidget: Widget {
    let kind = "LibraryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibraryProvider()) { entry in
            LibraryWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Library")
        .description("Quick access to your audiobooks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension SharedBookData {
    static let placeholders: [SharedBookData] = [
        SharedBookData(
            id: "p1",
            title: "The Great Gatsby",
            author: "F. Scott Fitzgerald",
            coverArtData: nil,
            progress: 0.34,
            currentTrackTitle: "Chapter 5",
            totalDuration: 28800,
            listenedDuration: 9792,
            lastPlayedAt: .now,
            isFavorite: true
        ),
        SharedBookData(
            id: "p2",
            title: "1984",
            author: "George Orwell",
            coverArtData: nil,
            progress: 0.67,
            currentTrackTitle: "Part Two, Chapter 3",
            totalDuration: 41400,
            listenedDuration: 27738,
            lastPlayedAt: .now.addingTimeInterval(-3600),
            isFavorite: false
        ),
    ]
}
