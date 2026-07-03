//
//  DownloadActivityWidget.swift
//  PagelessDownloadActivity
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DownloadActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        DownloadActivityWidget()
    }
}

struct DownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            DownloadLockScreenView(state: context.state)
                .widgetURL(DownloadActivityStyle.destinationURL)
                .activityBackgroundTint(DownloadActivityStyle.ink)
                .activitySystemActionForegroundColor(DownloadActivityStyle.paper)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DownloadImprintTile(state: context.state, size: 42)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .lineLimit(1)
                        Text(DownloadActivityStyle.statusText(context.state))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DownloadActivityStyle.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DownloadPercent(state: context.state, size: 14)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DownloadProgressRule(state: context.state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: DownloadActivityStyle.symbol(context.state.phase))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DownloadActivityStyle.tint(context.state.phase))
            } compactTrailing: {
                DownloadPercent(state: context.state, size: 11)
            } minimal: {
                DownloadMinimalGauge(state: context.state)
            }
            .keylineTint(DownloadActivityStyle.amber)
            .widgetURL(DownloadActivityStyle.destinationURL)
        }
    }
}

private struct DownloadLockScreenView: View {
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DownloadImprintTile(state: state, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(DownloadActivityStyle.eyebrow(state))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(DownloadActivityStyle.amber)
                    Text(state.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(DownloadActivityStyle.paper)
                        .lineLimit(1)
                    Text(DownloadActivityStyle.statusText(state))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DownloadActivityStyle.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                DownloadPercent(state: state, size: 15)
            }

            DownloadProgressRule(state: state)
        }
        .padding(15)
    }
}

private struct DownloadImprintTile: View {
    let state: DownloadActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(DownloadActivityStyle.paper)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(DownloadActivityStyle.amber.opacity(0.7), lineWidth: 1)
            Image(systemName: DownloadActivityStyle.symbol(state.phase))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(DownloadActivityStyle.tint(state.phase))
        }
        .frame(width: size, height: size)
    }
}

private struct DownloadPercent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: DownloadActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Text(DownloadActivityStyle.percent(state.progress))
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundStyle(DownloadActivityStyle.tint(state.phase))
            .contentTransition(reduceMotion ? .identity : .numericText())
    }
}

private struct DownloadMinimalGauge: View {
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        Gauge(value: DownloadActivityStyle.progress(state.progress)) {
            Image(systemName: "book.pages.fill")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(DownloadActivityStyle.tint(state.phase))
    }
}

private struct DownloadProgressRule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        GeometryReader { geometry in
            let progress = DownloadActivityStyle.progress(state.progress)
            ZStack(alignment: .leading) {
                Capsule().fill(DownloadActivityStyle.paper.opacity(0.16))
                Capsule()
                    .fill(DownloadActivityStyle.tint(state.phase))
                    .frame(width: max(4, geometry.size.width * progress))
                Rectangle()
                    .fill(DownloadActivityStyle.paper)
                    .frame(width: 2, height: 7)
                    .offset(x: max(1, geometry.size.width * progress - 1))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: progress)
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}

private enum DownloadActivityStyle {
    static let destinationURL = URL(string: "unpaged://library/downloads")!
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let paper = Color(red: 0.98, green: 0.95, blue: 0.89)
    static let amber = Color(red: 0.90, green: 0.60, blue: 0.10)
    static let muted = Color(red: 0.66, green: 0.64, blue: 0.61)

    static func progress(_ value: Double) -> Double { min(1, max(0, value)) }
    static func percent(_ value: Double) -> String { "\(Int((progress(value) * 100).rounded()))%" }

    static func tint(_ phase: DownloadActivityPhase) -> Color {
        phase == .failed ? .red : amber
    }

    static func symbol(_ phase: DownloadActivityPhase) -> String {
        switch phase {
        case .preparing: "book.closed.fill"
        case .downloading: "arrow.down"
        case .failed: "exclamationmark"
        case .complete: "checkmark"
        }
    }

    static func eyebrow(_ state: DownloadActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .preparing: "PREPARING"
        case .downloading: state.activeBookCount > 1 ? "UNPAGED · \(state.activeBookCount) BOOKS" : "UNPAGED · DOWNLOADING"
        case .failed: "DOWNLOAD PAUSED"
        case .complete: "READY TO LISTEN"
        }
    }

    static func statusText(_ state: DownloadActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .preparing: "Preparing chapters…"
        case .downloading: "\(state.completedTracks) of \(state.totalTracks) tracks"
        case .failed: state.failureMessage ?? "Open Unpaged to retry"
        case .complete: "Download complete"
        }
    }
}
