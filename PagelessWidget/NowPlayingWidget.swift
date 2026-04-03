//
//  NowPlayingWidget.swift
//  PagelessWidget
//

import SwiftUI
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let nowPlaying: SharedNowPlayingData?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, nowPlaying: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let entry = NowPlayingEntry(date: .now, nowPlaying: SharedDefaults.loadNowPlaying() ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = NowPlayingEntry(date: .now, nowPlaying: SharedDefaults.loadNowPlaying())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
        completion(timeline)
    }
}

struct NowPlayingWidgetEntryView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let np = entry.nowPlaying {
            switch family {
            case .systemSmall:
                smallView(np)
            case .systemMedium:
                mediumView(np)
            default:
                mediumView(np)
            }
        } else {
            emptyView
        }
    }

    private func smallView(_ np: SharedNowPlayingData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let coverData = np.coverArtData, let uiImage = UIImage(data: coverData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "book.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            Text(np.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            ProgressView(value: np.progress)
                .tint(.primary)

            Text(np.isPlaying ? "Playing" : "Paused")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .widgetURL(URL(string: "pageless://nowplaying"))
    }

    private func mediumView(_ np: SharedNowPlayingData) -> some View {
        HStack(spacing: 12) {
            if let coverData = np.coverArtData, let uiImage = UIImage(data: coverData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(np.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(np.trackTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: np.progress)
                    .tint(.primary)

                HStack {
                    Text(np.isPlaying ? "Playing" : "Paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(np.currentTime) + " / " + formatTime(np.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .widgetURL(URL(string: "pageless://nowplaying"))
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Nothing Playing")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .widgetURL(URL(string: "pageless://library"))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct NowPlayingWidget: Widget {
    let kind = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now Playing")
        .description("See what you're currently listening to.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension SharedNowPlayingData {
    static let placeholder = SharedNowPlayingData(
        bookID: "placeholder",
        title: "The Great Gatsby",
        author: "F. Scott Fitzgerald",
        coverArtData: nil,
        trackTitle: "Chapter 1",
        currentTime: 1234,
        duration: 3600,
        isPlaying: true,
        playbackRate: 1.0,
        progress: 0.34
    )
}
