//
//  ReadingActivityCard.swift
//  Pageless
//

import SwiftUI

/// Compact card on the Favorites tab. Tap pushes `ReadingStatsView` with a zoom morph
/// anchored on the heatmap.
struct ReadingActivityCard: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    var dailyGoalMinutes: Int = 0
    var morphNamespace: Namespace.ID
    var morphID: String

    @Environment(\.colorScheme) private var colorScheme

    private var scale: HeatmapScale { .pick(daysSinceFirst: stats.daysTracked) }

    private var subtitle: String {
        switch scale {
        case .week:      return "Last 7 days"
        case .month:     return "Last 30 days"
        case .fourMonth: return "Last 4 months"
        }
    }

    private var cellSize: CGFloat {
        switch scale {
        case .week:      return 30
        case .month:     return 9
        case .fourMonth: return 11
        }
    }
    private var gap: CGFloat {
        switch scale {
        case .week:      return 7
        case .month:     return 2
        case .fourMonth: return 3
        }
    }
    private var radius: CGFloat {
        switch scale {
        case .week:      return 6
        case .month:     return 2
        case .fourMonth: return 2
        }
    }

    private var gridModel: HeatmapGridModel {
        HeatmapGridModel.build(
            scale: scale,
            today: stats.today,
            firstDay: stats.firstDay,
            activityByDay: stats.activityByDay
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heatmap
            footer
            if dailyGoalMinutes > 0 {
                dailyGoalRow
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(fmtHoursMins(stats.totalMinutes))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("· \(subtitle)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var heatmap: some View {
        HStack {
            Spacer(minLength: 0)
            ReadingHeatmapView(
                model: gridModel,
                palette: palette,
                cellSize: cellSize,
                gap: gap,
                radius: radius,
                showLabels: true,
                stagger: false
            )
            .matchedTransitionSource(id: morphID, in: morphNamespace)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            streakChip
            Spacer(minLength: 4)
            HeatmapLegend(palette: palette)
        }
        .padding(.top, 2)
    }

    private var streakChip: some View {
        let accent = palette.accent(forScheme: colorScheme)
        return HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .shadow(color: accent.opacity(0.6), radius: 3)
            Text(streakLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readingActivity.streak")
    }

    private var dailyGoalRow: some View {
        let accent = palette.accent(forScheme: colorScheme)
        let progress = min(1.0, Double(stats.todayMinutes) / Double(max(1, dailyGoalMinutes)))
        let met = stats.todayMinutes >= dailyGoalMinutes

        return VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 8) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(fmtHoursMins(stats.todayMinutes)) / \(fmtHoursMins(dailyGoalMinutes))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Spacer(minLength: 4)
                if met {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Goal met")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(progress > 0 ? 6 : 0, geo.size.width * progress))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readingActivity.goal")
    }

    private var streakLabel: String {
        if stats.currentStreak > 0 {
            return stats.isStreakActiveToday
                ? "\(stats.currentStreak)-day streak"
                : "\(stats.currentStreak)-day streak · listen today"
        }
        return "Start a streak today"
    }
}

// MARK: - shared formatters

func fmtHoursMins(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m)m" }
    if m == 0 { return "\(h)h" }
    return "\(h)h \(m)m"
}

func fmtClock12(_ hour: Int) -> String {
    if hour == 0 { return "12 AM" }
    if hour < 12 { return "\(hour) AM" }
    if hour == 12 { return "12 PM" }
    return "\(hour - 12) PM"
}
