//
//  PagelessLiveActivityView.swift
//  PagelessWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

struct PagelessLiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PagelessPlaybackAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.bookTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(context.attributes.author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                            .tint(.white)
                        HStack {
                            Text(context.state.trackTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatTime(context.state.currentTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.primary)
            } compactTrailing: {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.circular)
                    .tint(.primary)
                    .frame(width: 16, height: 16)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "book.fill")
                    .foregroundStyle(.primary)
            }
            .widgetURL(URL(string: "pageless://nowplaying"))
        }
    }

    private func lockScreenView(context: ActivityViewContext<PagelessPlaybackAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.bookTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(context.state.trackTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: context.state.progress)
                    .tint(.primary)
            }

            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(.primary)
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.7))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
