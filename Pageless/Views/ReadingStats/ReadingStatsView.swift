//
//  ReadingStatsView.swift
//  Pageless
//

import SwiftUI
import UIKit

/// Full-screen reading stats. Pushed from Favorites (with zoom transition) or from Settings.
///
/// Choreography:
/// - The pushed view itself uses `.navigationTransition(.zoom(...))` when opened from Favorites.
/// - Each section uses `revealOnAppear` (LazyVStack ensures appearance fires near visibility),
///   and key numerics use `CountUpText`.
/// - The custom nav bar fades its title + border in as you scroll past the hero, and hosts the
///   lazy `ShareLink` when there is activity.
/// - The hero parallaxes out (fades + drifts up 40pt) over the first 320pt of scroll.
struct ReadingStatsView: View {
    let stats: ReadingStats
    @Binding var palette: HeatmapPalette
    @Binding var dailyGoalMinutes: Int
    var bookCovers: [UUID: UIImage] = [:]
    var backLabel: String = "Library"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedDayKey: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            Color.cream.ignoresSafeArea()

            if stats.hasAnyActivity {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        // Tap-target spacer so the custom nav bar (overlaid below) doesn't
                        // sit on top of content. Matches the nav bar's height.
                        Color.clear.frame(height: 44)

                        StatsHeroSection(
                            stats: stats,
                            palette: palette,
                            scrollOffset: scrollOffset,
                            selectedDayKey: selectedDayKey,
                            onSelectDay: handleDaySelection
                        )

                        if dailyGoalMinutes > 0 {
                            DailyGoalProgressSection(
                                stats: stats,
                                dailyGoalMinutes: dailyGoalMinutes,
                                palette: palette
                            )
                        }

                        StatsPreferencesSection(
                            palette: $palette,
                            dailyGoalMinutes: $dailyGoalMinutes
                        )

                        Rectangle()
                            .fill(separatorColor)
                            .frame(height: 1)
                            .padding(.horizontal, 20)

                        TotalTimeSection(stats: stats, palette: palette)
                        BestDaySection(
                            stats: stats,
                            palette: palette,
                            coverImage: stats.bestDay?.topBookID.flatMap { bookCovers[$0] }
                        )
                        BestTimeSection(stats: stats, palette: palette)
                        LongestBookSection(
                            stats: stats,
                            palette: palette,
                            coverImage: stats.longestBookID.flatMap { bookCovers[$0] }
                        )
                        TopBooksSection(
                            stats: stats,
                            palette: palette,
                            bookCovers: bookCovers
                        )
                        StreakSection(stats: stats, palette: palette)
                        MetricsTrioSection(stats: stats, palette: palette)
                        if stats.freeMinutes > 0 {
                            FreeBooksSection(stats: stats, palette: palette)
                        }

                        StatsFooter(backLabel: backLabel, onClose: { dismiss() })
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }
            } else {
                ReadingStatsEmptyState(
                    backLabel: backLabel,
                    onClose: { dismiss() }
                )
            }

            navBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func handleDaySelection(_ cell: HeatmapCellInfo) {
        guard !cell.isFuture else { return }
        withAnimation(.snappy(duration: 0.22)) {
            if selectedDayKey == cell.dayKey {
                selectedDayKey = nil
            } else {
                selectedDayKey = cell.dayKey
            }
        }
    }

    // MARK: - Nav bar

    private var navBarProgress: Double {
        guard stats.hasAnyActivity else { return 0 }
        return Double(max(0, min(1, (scrollOffset - 80) / 180)))
    }

    private var navBar: some View {
        ZStack {
            // Background that fades from clear cream → blurred cream as user scrolls
            Rectangle()
                .fill(Color.cream)
                .opacity(navBarProgress * 0.85)
                .background(.ultraThinMaterial.opacity(navBarProgress > 0.2 ? 1 : 0))
                .ignoresSafeArea(edges: .top)

            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(backLabel)
                            .font(.system(size: 17))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)

                Spacer()

                if stats.hasAnyActivity {
                    ShareLink(
                        item: ReadingStatsShareImage(stats: stats, palette: palette),
                        preview: SharePreview("Reading Activity")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share reading activity")
                    .accessibilityIdentifier("readingStats.share")
                    .padding(.trailing, 8)
                }
            }
            .frame(height: 44)

            Text("Reading")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .opacity(navBarProgress > 0.5 ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (navBarProgress > 0.5 ? 0 : 6))
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .easeOut(duration: 0.25),
                    value: navBarProgress > 0.5
                )
        }
        .frame(height: 44)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 0.5)
                .opacity(navBarProgress > 0.5 ? 1 : 0)
        }
    }

    private var separatorColor: Color {
        Color.primary.opacity(0.12)
    }
}
