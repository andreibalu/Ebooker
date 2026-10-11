import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private struct ListeningSnapshot: Decodable {
    let bookID: UUID
    let title: String
    let author: String
    let progress: Double
    let timeLeft: Double
    let lastPlayedAt: Date
}

private struct ListeningEntry: TimelineEntry {
    let date: Date
    let snapshot: ListeningSnapshot?
    let cover: UIImage?

    static let preview = ListeningEntry(date: .now, snapshot: ListeningSnapshot(
        bookID: UUID(), title: "Pride and Prejudice", author: "Jane Austen",
        progress: 0.42, timeLeft: 10800, lastPlayedAt: .now), cover: nil)
}

private struct ListeningProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListeningEntry { .preview }
    func getSnapshot(in context: Context, completion: @escaping (ListeningEntry) -> Void) {
        completion(context.isPreview ? .preview : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ListeningEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> ListeningEntry {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.andreibaludev.Pageless")
        let snapshot = container.flatMap { try? Data(contentsOf: $0.appendingPathComponent("continue-listening.json")) }
            .flatMap { try? JSONDecoder().decode(ListeningSnapshot.self, from: $0) }
        let cover = snapshot.flatMap { book in
            container.flatMap { UIImage(contentsOfFile: $0.appendingPathComponent("\(book.bookID.uuidString).jpg").path) }
        }
        return ListeningEntry(date: .now, snapshot: snapshot, cover: cover)
    }
}

struct ContinueListeningWidget: Widget {
    let kind = "ContinueListening"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListeningProvider()) { entry in
            ListeningWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: entry.snapshot == nil ? "unpaged://library" : "unpaged://resume"))
        }
        .configurationDisplayName("Continue Listening")
        .description("Resume your last audiobook in Unpaged.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

private struct ListeningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ListeningEntry

    var body: some View {
        Group {
            if let book = entry.snapshot {
                if family == .accessoryCircular {
                    Gauge(value: book.progress) {
                        Image(systemName: "headphones")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .accessibilityLabel(book.title)
                    .accessibilityValue("\(Int(book.progress * 100)) percent")
                    .accessibilityIdentifier("widget.progressRing")
                } else if family == .accessoryRectangular {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline).lineLimit(1)
                            .accessibilityIdentifier("widget.title")
                        progress(book)
                    }
                } else if family == .systemMedium {
                    HStack(spacing: 12) {
                        cover.frame(width: 78, height: 110)
                        VStack(alignment: .leading, spacing: 5) {
                            metadata(book)
                            progress(book)
                            HStack {
                                timeLeft(book)
                                Spacer(minLength: 0)
                                Button(intent: PlayLatestBookIntent()) {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("widget.play")
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top, spacing: 8) {
                            cover.frame(width: 42, height: 54)
                            metadata(book)
                        }
                        Spacer(minLength: 0)
                        progress(book)
                        timeLeft(book)
                    }
                }
            } else {
                Text("Start a book in Unpaged")
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("widget.empty")
            }
        }
        .tint(.orange)
        .accessibilityIdentifier("widget.continueListening")
    }

    private var cover: some View {
        Group {
            if let image = entry.cover {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            } else {
                // Placeholder only. Generated covers are rendered and saved by the app.
                Color.secondary.opacity(0.15)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }

    private func metadata(_ book: ListeningSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.title).font(.headline).fontDesign(.serif).lineLimit(2)
                .accessibilityIdentifier("widget.title")
            Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("widget.author")
        }
    }

    private func progress(_ book: ListeningSnapshot) -> some View {
        ProgressView(value: min(1, max(0, book.progress)))
            .widgetAccentable()
            .accessibilityLabel("Listening progress")
            .accessibilityIdentifier("widget.progress")
    }

    private func timeLeft(_ book: ListeningSnapshot) -> some View {
        Text("\(Int(ceil(book.timeLeft / 60))) min left")
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .accessibilityIdentifier("widget.timeLeft")
    }
}

#if DEBUG
private struct ContinueListeningWidgetPreviews: PreviewProvider {
    static var previews: some View {
        ListeningWidgetView(entry: .preview)
            .containerBackground(.background, for: .widget)
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small")
        ListeningWidgetView(entry: .preview)
            .containerBackground(.background, for: .widget)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Medium")
        ListeningWidgetView(entry: .preview)
            .containerBackground(.background, for: .widget)
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
            .previewDisplayName("Rectangular")
        ListeningWidgetView(entry: .preview)
            .containerBackground(.background, for: .widget)
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            .previewDisplayName("Circular")
    }
}
#endif
