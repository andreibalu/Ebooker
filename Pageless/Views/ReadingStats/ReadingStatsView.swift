//
//  ReadingStatsView.swift
//  Pageless
//

import SwiftUI

/// Full-screen reading stats. Pushed onto the nav stack from the Favorites tab.
///
/// Choreography:
/// - The pushed view itself uses `.navigationTransition(.zoom(...))` so it appears
///   to morph out of the small `ReadingActivityCard`'s heatmap.
/// - Each section uses `revealOnAppear` (LazyVStack ensures appearance fires near
///   visibility), and key numerics use `CountUpText`.
/// - The custom nav bar fades its title + border in as you scroll past the hero.
/// - The hero parallaxes out (fades + drifts up 40pt) over the first 320pt of scroll.
struct ReadingStatsView: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber

    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.cream.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    // Tap-target spacer so the custom nav bar (overlaid below) doesn't
                    // sit on top of content. Matches the nav bar's height.
                    Color.clear.frame(height: 44)

                    StatsHeroSection(
                        stats: stats,
                        palette: palette,
                        scrollOffset: scrollOffset
                    )

                    Rectangle()
                        .fill(separatorColor)
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    TotalTimeSection(stats: stats, palette: palette)
                    BestDaySection(stats: stats, palette: palette)
                    BestTimeSection(stats: stats, palette: palette)
                    LongestBookSection(stats: stats, palette: palette)
                    StreakSection(stats: stats, palette: palette)
                    MetricsTrioSection(stats: stats, palette: palette)
                    FreeBooksSection(stats: stats, palette: palette)

                    StatsFooter(onClose: { dismiss() })
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                scrollOffset = newValue
            }

            navBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Nav bar

    private var navBarProgress: Double {
        Double(max(0, min(1, (scrollOffset - 80) / 180)))
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
                        Text("Library")
                            .font(.system(size: 17))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)

                Spacer()
            }
            .frame(height: 44)

            Text("Reading")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .opacity(navBarProgress > 0.5 ? 1 : 0)
                .offset(y: navBarProgress > 0.5 ? 0 : 6)
                .animation(.easeOut(duration: 0.25), value: navBarProgress > 0.5)
        }
        .frame(height: 44)
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
