//
//  ReadingStatsShareCard.swift
//  Pageless
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Daily listening goal preference

enum DailyListeningGoal {
    static let storageKey = "dailyListeningGoalMinutes"
    static let presets: [Int] = [0, 15, 30, 45, 60]

    static func label(for minutes: Int) -> String {
        minutes == 0 ? "Off" : "\(minutes)m"
    }
}

// MARK: - Share payload (privacy-safe: no book titles or authors)

struct ReadingStatsSharePayload: Sendable {
    let totalMinutes: Int
    let currentStreak: Int
    let longestStreak: Int
    let booksFinished: Int
    let today: Date
    let firstDay: Date
    let minutesByDay: [String: Int]
    let palette: HeatmapPalette

    init(stats: ReadingStats, palette: HeatmapPalette) {
        self.totalMinutes = stats.totalMinutes
        self.currentStreak = stats.currentStreak
        self.longestStreak = stats.longestStreak
        self.booksFinished = stats.booksFinished
        self.today = stats.today
        self.firstDay = stats.firstDay
        self.minutesByDay = stats.activityByDay.mapValues(\.minutes)
        self.palette = palette
    }
}

// MARK: - Lazy Transferable PNG

/// Renders the share card PNG lazily only when the user actually triggers sharing, never inside `body`.
struct ReadingStatsShareImage: Transferable, Sendable {
    let payload: ReadingStatsSharePayload

    init(stats: ReadingStats, palette: HeatmapPalette) {
        self.payload = ReadingStatsSharePayload(stats: stats, palette: palette)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderPNGData()
        }
    }

    @MainActor
    func renderPNGData() throws -> Data {
        let card = ReadingStatsShareCardView(payload: payload)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage,
              let data = uiImage.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

// MARK: - Editorial share card (explicit light colors, pinned Dynamic Type, no titles/authors)

struct ReadingStatsShareCardView: View {
    let payload: ReadingStatsSharePayload

    // Explicit non-dynamic light colors so off-screen ImageRenderer never resolves dark-mode UIColors.
    private static let creamBG = Color(red: 0.97, green: 0.955, blue: 0.93)
    private static let cardSurface = Color(red: 1.0, green: 0.99, blue: 0.97)
    private static let primaryInk = Color(red: 0.12, green: 0.11, blue: 0.10)
    private static let secondaryInk = Color(red: 0.42, green: 0.40, blue: 0.37)
    private static let hairline = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.10)

    private var accent: Color {
        payload.palette.accent(forScheme: .light)
    }

    private var heatmapModel: HeatmapGridModel {
        let activity: [String: ReadingDayActivity] = payload.minutesByDay.reduce(into: [:]) { acc, pair in
            acc[pair.key] = ReadingDayActivity(
                dayKey: pair.key,
                date: payload.today,
                minutes: pair.value,
                topBookID: nil,
                topBookTitle: nil
            )
        }
        return HeatmapGridModel.buildGrid(
            weekCount: 12,
            today: payload.today,
            firstDay: payload.firstDay,
            activityByDay: activity
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("READING ACTIVITY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Self.secondaryInk)
                Spacer()
                Text("LAST 12 WEEKS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Self.secondaryInk.opacity(0.8))
            }

            // Total time hero
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(fmtHoursMins(payload.totalMinutes))
                    .font(.system(size: 54, weight: .semibold, design: .serif))
                    .kerning(-1.0)
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("listened")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(Self.secondaryInk)
            }
            .padding(.top, 10)

            // 12-week mini heatmap card
            VStack(spacing: 10) {
                ReadingHeatmapView(
                    model: heatmapModel,
                    palette: payload.palette,
                    cellSize: 16,
                    gap: 4,
                    radius: 3.5,
                    showLabels: false,
                    stagger: false,
                    colorSchemeOverride: .light
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(Self.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Self.hairline, lineWidth: 1)
            )
            .padding(.top, 18)

            // 3-up metrics row
            HStack(spacing: 10) {
                statTile(
                    label: "STREAK",
                    value: "\(payload.currentStreak)d",
                    accentValue: payload.currentStreak > 0
                )
                statTile(
                    label: "LONGEST",
                    value: "\(payload.longestStreak)d",
                    accentValue: false
                )
                statTile(
                    label: "FINISHED",
                    value: "\(payload.booksFinished)",
                    accentValue: false
                )
            }
            .padding(.top, 14)

            Spacer(minLength: 14)

            Rectangle()
                .fill(Self.hairline)
                .frame(height: 1)

            // Brand footer
            HStack(spacing: 8) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text("UNPAGED")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .tracking(2.4)
                    .foregroundStyle(Self.primaryInk)
                Spacer()
                Text("Audiobook player")
                    .font(.system(size: 11))
                    .foregroundStyle(Self.secondaryInk)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 360, height: 450)
        .background(Self.creamBG)
    }

    private func statTile(label: String, value: String, accentValue: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Self.secondaryInk)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(accentValue ? accent : Self.primaryInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Self.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Self.hairline, lineWidth: 1)
        )
    }
}
