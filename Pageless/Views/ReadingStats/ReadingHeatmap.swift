//
//  ReadingHeatmap.swift
//  Pageless
//

import SwiftUI

// MARK: - Palette

enum HeatmapPalette: String, CaseIterable {
    case amber, burgundy, mono

    static let levelCount = 5

    private static let amberLight:    [Color] = ["ECE4D2","F3D9A8","E8B36C","CC8632","995510"].map(Color.init(hex:))
    private static let amberDark:     [Color] = ["2A2722","4A3C26","7B5C2A","B07A1F","E59A19"].map(Color.init(hex:))
    private static let burgundyLight: [Color] = ["EBE2DE","E6C5BD","CE8C82","A04A4F","6B2024"].map(Color.init(hex:))
    private static let burgundyDark:  [Color] = ["2A2724","4E342E","7C3D3F","A24A50","C56163"].map(Color.init(hex:))
    private static let monoLight:     [Color] = ["E8E3D6","C8C0AE","9A917D","5F584A","23201A"].map(Color.init(hex:))
    private static let monoDark:      [Color] = ["2C2925","4A463E","75705F","A09A86","E7E1CF"].map(Color.init(hex:))

    func colors(forScheme scheme: ColorScheme) -> [Color] {
        let isDark = scheme == .dark
        switch self {
        case .amber:    return isDark ? Self.amberDark    : Self.amberLight
        case .burgundy: return isDark ? Self.burgundyDark : Self.burgundyLight
        case .mono:     return isDark ? Self.monoDark     : Self.monoLight
        }
    }

    /// Accent for chips, count-up numbers, polar bar highlight, free-books ring.
    var accent: Color {
        switch self {
        case .amber:    return Color(hex: "CC8632")
        case .burgundy: return Color(hex: "A04A4F")
        case .mono:     return Color(hex: "23201A")
        }
    }

    static func level(forMinutes m: Int) -> Int {
        if m <= 0 { return 0 }
        if m < 15 { return 1 }
        if m < 30 { return 2 }
        if m < 60 { return 3 }
        return 4
    }

    func color(forMinutes m: Int, scheme: ColorScheme) -> Color {
        colors(forScheme: scheme)[Self.level(forMinutes: m)]
    }
}

// MARK: - Time scale

enum HeatmapScale {
    case week        // 7 days, single row, per-cell weekday labels
    case month       // 30 days, single row, month-boundary labels
    case fourMonth   // 18 weeks × 7 days grid

    var weekCount: Int {
        switch self {
        case .week:      return 1
        case .month:     return 1
        case .fourMonth: return 18
        }
    }

    var layout: HeatmapLayout {
        switch self {
        case .week:      return .linearWithDayLabels
        case .month:     return .linearWithMonthLabels
        case .fourMonth: return .grid
        }
    }

    /// Number of cells in linear layouts. 0 for grid scales.
    var linearDayCount: Int {
        switch self {
        case .week:      return 7
        case .month:     return 30
        case .fourMonth: return 0
        }
    }

    static func pick(daysSinceFirst: Int) -> HeatmapScale {
        if daysSinceFirst <= 7 { return .week }
        if daysSinceFirst <= 30 { return .month }
        return .fourMonth
    }
}

enum HeatmapLayout {
    case grid                   // weeks × 7 days
    case linearWithDayLabels    // horizontal row, 3-letter weekday above each cell
    case linearWithMonthLabels  // horizontal row, month name at boundaries
}

// MARK: - Grid model

struct HeatmapCellInfo: Equatable {
    let date: Date
    let dayKey: String
    let minutes: Int
    let isFuture: Bool
    let isBeforeStart: Bool
    let isToday: Bool
    let dow: Int        // 0 = Mon ... 6 = Sun
}

struct HeatmapMonthLabel: Equatable {
    let colIdx: Int
    let label: String
}

struct HeatmapGridModel {
    let cols: [[HeatmapCellInfo]]      // populated for .grid layout
    let linearDays: [HeatmapCellInfo]  // populated for linear layouts
    let monthLabels: [HeatmapMonthLabel]
    let scale: HeatmapScale
    let layout: HeatmapLayout
    let firstDay: Date
    let today: Date

    static func build(
        scale: HeatmapScale,
        today: Date,
        firstDay: Date,
        activityByDay: [String: ReadingDayActivity],
        calendar: Calendar = .current
    ) -> HeatmapGridModel {
        let todayStart = calendar.startOfDay(for: today)
        switch scale.layout {
        case .grid:
            return buildGrid(
                scale: scale, today: todayStart, firstDay: firstDay,
                activityByDay: activityByDay, calendar: calendar
            )
        case .linearWithDayLabels, .linearWithMonthLabels:
            return buildLinear(
                scale: scale, today: todayStart, firstDay: firstDay,
                activityByDay: activityByDay, calendar: calendar
            )
        }
    }

    private static func buildGrid(
        scale: HeatmapScale,
        today: Date,
        firstDay: Date,
        activityByDay: [String: ReadingDayActivity],
        calendar: Calendar
    ) -> HeatmapGridModel {
        let nw = scale.weekCount
        let monThis = mondayOf(today, calendar: calendar)
        guard let start = calendar.date(byAdding: .day, value: -(nw - 1) * 7, to: monThis) else {
            return HeatmapGridModel(
                cols: [], linearDays: [], monthLabels: [],
                scale: scale, layout: .grid, firstDay: firstDay, today: today
            )
        }

        let todayKey = ReadingSession.makeDayKey(date: today, calendar: calendar)
        var cols: [[HeatmapCellInfo]] = []
        var monthLabels: [HeatmapMonthLabel] = []
        var lastMonth = -1

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "en_US_POSIX")
        monthFmt.dateFormat = "LLL"   // short month, "Jan"

        for w in 0..<nw {
            guard let colStart = calendar.date(byAdding: .day, value: w * 7, to: start) else { continue }
            var days: [HeatmapCellInfo] = []
            for r in 0..<7 {
                guard let d = calendar.date(byAdding: .day, value: r, to: colStart) else { continue }
                let dStart = calendar.startOfDay(for: d)
                let key = ReadingSession.makeDayKey(date: dStart, calendar: calendar)
                let minutes = activityByDay[key]?.minutes ?? 0
                let isFuture = dStart > today
                let beforeStart = dStart < firstDay
                days.append(HeatmapCellInfo(
                    date: dStart,
                    dayKey: key,
                    minutes: minutes,
                    isFuture: isFuture,
                    isBeforeStart: beforeStart,
                    isToday: key == todayKey,
                    dow: r
                ))
            }
            if let firstOfMonth = days.first(where: { calendar.component(.day, from: $0.date) <= 7 && !$0.isBeforeStart }) {
                let m = calendar.component(.month, from: firstOfMonth.date)
                if m != lastMonth {
                    monthLabels.append(HeatmapMonthLabel(colIdx: w, label: monthFmt.string(from: firstOfMonth.date)))
                    lastMonth = m
                }
            }
            cols.append(days)
        }
        return HeatmapGridModel(
            cols: cols, linearDays: [], monthLabels: monthLabels,
            scale: scale, layout: .grid, firstDay: firstDay, today: today
        )
    }

    private static func buildLinear(
        scale: HeatmapScale,
        today: Date,
        firstDay: Date,
        activityByDay: [String: ReadingDayActivity],
        calendar: Calendar
    ) -> HeatmapGridModel {
        let n = scale.linearDayCount
        let layout = scale.layout
        let todayKey = ReadingSession.makeDayKey(date: today, calendar: calendar)

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "en_US_POSIX")
        monthFmt.dateFormat = "LLL"

        var days: [HeatmapCellInfo] = []
        var monthLabels: [HeatmapMonthLabel] = []
        var lastMonth = -1

        for i in 0..<n {
            // i = 0 is the oldest cell in the row, i = n - 1 is today.
            let offset = (n - 1) - i
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dStart = calendar.startOfDay(for: d)
            let key = ReadingSession.makeDayKey(date: dStart, calendar: calendar)
            let minutes = activityByDay[key]?.minutes ?? 0
            let isFuture = dStart > today
            let beforeStart = dStart < firstDay
            let weekday = calendar.component(.weekday, from: dStart) // 1 = Sunday
            let dow = (weekday + 5) % 7 // 0 = Mon
            days.append(HeatmapCellInfo(
                date: dStart,
                dayKey: key,
                minutes: minutes,
                isFuture: isFuture,
                isBeforeStart: beforeStart,
                isToday: key == todayKey,
                dow: dow
            ))

            if layout == .linearWithMonthLabels && !beforeStart {
                let m = calendar.component(.month, from: dStart)
                if m != lastMonth {
                    monthLabels.append(HeatmapMonthLabel(colIdx: i, label: monthFmt.string(from: dStart)))
                    lastMonth = m
                }
            }
        }

        return HeatmapGridModel(
            cols: [], linearDays: days, monthLabels: monthLabels,
            scale: scale, layout: layout, firstDay: firstDay, today: today
        )
    }

    private static func mondayOf(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start) // 1 = Sunday
        // days since Monday: Mon→0, Tue→1, ..., Sun→6
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }
}

// MARK: - The view

struct ReadingHeatmapView: View {
    let model: HeatmapGridModel
    var palette: HeatmapPalette = .amber
    var cellSize: CGFloat = 12
    var gap: CGFloat = 3
    var radius: CGFloat = 3
    var showLabels: Bool = true
    /// When true, each cell fades + scales in with a (col+row) stagger.
    var stagger: Bool = false
    /// Optional emphasis ring (e.g. best-day marker).
    var emphasizeKey: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var didAppear = false

    var body: some View {
        Group {
            switch model.layout {
            case .grid:
                gridBody
            case .linearWithDayLabels:
                linearBody(showDayLabels: true)
            case .linearWithMonthLabels:
                linearBody(showDayLabels: false)
            }
        }
        .onAppear {
            // Trigger the stagger animation once layout is done.
            if stagger { didAppear = true }
        }
    }

    // MARK: grid (four-month)

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showLabels { monthLabelsRow }

            HStack(alignment: .top, spacing: 6) {
                if showLabels { yAxisLabels }
                cellsGrid
            }
        }
    }

    // MARK: linear (week / month)

    private func linearBody(showDayLabels: Bool) -> some View {
        let days = model.linearDays
        return VStack(alignment: .leading, spacing: 6) {
            if showLabels && !showDayLabels {
                linearMonthLabelsRow(days: days)
            }
            if showLabels && showDayLabels {
                HStack(spacing: gap) {
                    ForEach(Array(days.enumerated()), id: \.offset) { (_, cell) in
                        Text(Self.dayShortLabels[cell.dow])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(secondaryLabelColor)
                            .frame(width: cellSize)
                    }
                }
            }
            HStack(spacing: gap) {
                ForEach(Array(days.enumerated()), id: \.offset) { (i, cell) in
                    cellView(cell, col: i, row: 0)
                }
            }
        }
    }

    private func linearMonthLabelsRow(days: [HeatmapCellInfo]) -> some View {
        let totalW: CGFloat = CGFloat(days.count) * cellSize + CGFloat(max(0, days.count - 1)) * gap
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 14)
            ForEach(model.monthLabels, id: \.colIdx) { ml in
                Text(ml.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(secondaryLabelColor.opacity(0.9))
                    .offset(x: CGFloat(ml.colIdx) * (cellSize + gap), y: 0)
            }
        }
        .frame(width: max(totalW, 0), height: 14, alignment: .leading)
    }

    private static let dayShortLabels: [String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // MARK: subviews

    private var monthLabelsRow: some View {
        let labelW: CGFloat = 30
        let totalW: CGFloat = CGFloat(model.cols.count) * cellSize + CGFloat(max(0, model.cols.count - 1)) * gap
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 14)
            ForEach(model.monthLabels, id: \.colIdx) { ml in
                Text(ml.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(secondaryLabelColor.opacity(0.9))
                    .offset(x: labelW + CGFloat(ml.colIdx) * (cellSize + gap), y: 0)
            }
        }
        .frame(width: max(totalW + labelW, 0), height: 14, alignment: .leading)
    }

    private var yAxisLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            ForEach(0..<7, id: \.self) { i in
                Text(dayLabels[i])
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(secondaryLabelColor)
                    .frame(width: 24, height: cellSize, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var cellsGrid: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(model.cols.enumerated()), id: \.offset) { (wi, col) in
                VStack(spacing: gap) {
                    ForEach(Array(col.enumerated()), id: \.offset) { (di, cell) in
                        cellView(cell, col: wi, row: di)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: HeatmapCellInfo, col: Int, row: Int) -> some View {
        let fill: Color = {
            if cell.isFuture || cell.isBeforeStart {
                return colorScheme == .dark
                    ? Color.white.opacity(0.025)
                    : Color.black.opacity(0.025)
            }
            return palette.color(forMinutes: cell.minutes, scheme: colorScheme)
        }()
        let ringed = (emphasizeKey == cell.dayKey)
        let todayRing = (cell.isToday && !cell.isFuture)

        let staggerDelay: Double = {
            guard stagger else { return 0 }
            // Approximation of the JS perCellMs = round(420 / cols). Cap at 14ms.
            let n = max(1, model.layout == .grid ? model.cols.count : model.linearDays.count)
            let perCell = min(14.0, max(5.0, 420.0 / Double(n)))
            return Double(col + row) * (perCell / 1000.0)
        }()

        let visible = !stagger || didAppear

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if ringed {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white : Color.black,
                            lineWidth: 1.5
                        )
                } else if todayRing {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.45),
                            lineWidth: 1
                        )
                }
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.6)
            .animation(
                stagger
                    ? .easeOut(duration: 0.48).delay(staggerDelay)
                    : nil,
                value: didAppear
            )
    }

    private var secondaryLabelColor: Color {
        colorScheme == .dark
            ? Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.55)
            : Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.55)
    }

    private let dayLabels: [String] = ["Mon", "", "Wed", "", "Fri", "", ""]
}

// MARK: - Legend

struct HeatmapLegend: View {
    var palette: HeatmapPalette = .amber
    var size: CGFloat = 9
    var gap: CGFloat = 3
    var radius: CGFloat = 2

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(spacing: gap) {
                ForEach(0..<HeatmapPalette.levelCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(palette.colors(forScheme: colorScheme)[i])
                        .frame(width: size, height: size)
                }
            }
            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color hex helper

extension Color {
    nonisolated init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
