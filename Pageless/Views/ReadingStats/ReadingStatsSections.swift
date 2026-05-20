//
//  ReadingStatsSections.swift
//  Pageless
//

import SwiftUI

// MARK: - Eyebrow / serif helpers

struct StatsEyebrow: View {
    let text: String
    var color: Color? = nil
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(color ?? .secondary)
    }
}

struct SerifDisplay: View {
    let text: String
    var size: CGFloat = 52
    var color: Color = .primary
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .serif))
            .kerning(-size * 0.02)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

// MARK: - Reveal on appear

/// Fades in + translates up + scales from 0.985 once the view appears (LazyVStack ensures
/// this fires near visibility, matching the JS intersection-observer trigger).
struct RevealOnAppear: ViewModifier {
    var delay: Double = 0
    var yOffset: CGFloat = 28
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.985)
            .offset(y: visible ? 0 : yOffset)
            .onAppear {
                guard !visible else { return }
                withAnimation(.easeOut(duration: 0.9).delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func revealOnAppear(delay: Double = 0, y: CGFloat = 28) -> some View {
        modifier(RevealOnAppear(delay: delay, yOffset: y))
    }
}

// MARK: - Count up

/// Animates a Double from 0 to `target` over `duration` with the chosen easing.
/// Re-runs when `trigger` flips from false → true. Renders via `format` closure.
struct CountUpText<Content: View>: View {
    let target: Double
    var duration: Double = 1.4
    var ease: Ease = .easeOutCubic
    var trigger: Bool = true
    @ViewBuilder let content: (Double) -> Content

    enum Ease { case easeOutCubic, easeOutQuart, easeOutQuint }

    @State private var startDate: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: !trigger || isDone)) { ctx in
            let raw = max(0, ctx.date.timeIntervalSince(startDate ?? ctx.date))
            let t = min(1, raw / duration)
            let eased = applyEase(t)
            content(target * eased)
        }
        .onAppear { if trigger, startDate == nil { startDate = .now } }
        .onChange(of: trigger) { _, newValue in
            if newValue, startDate == nil { startDate = .now }
        }
    }

    private var isDone: Bool {
        guard let s = startDate else { return false }
        return Date().timeIntervalSince(s) >= duration
    }

    private func applyEase(_ t: Double) -> Double {
        switch ease {
        case .easeOutCubic: return 1 - pow(1 - t, 3)
        case .easeOutQuart: return 1 - pow(1 - t, 4)
        case .easeOutQuint: return 1 - pow(1 - t, 5)
        }
    }
}

// MARK: - Hero

struct StatsHeroSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    let scrollOffset: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var scale: HeatmapScale { .pick(daysSinceFirst: stats.daysTracked) }

    private var heroCell: CGFloat {
        switch scale {
        case .fourMonth: return 14
        case .month:     return 10
        case .week:      return 40
        }
    }
    private var heroGap: CGFloat {
        switch scale {
        case .fourMonth: return 4
        case .month:     return 2
        case .week:      return 10
        }
    }
    private var heroRad: CGFloat {
        switch scale {
        case .fourMonth: return 3
        case .month:     return 2
        case .week:      return 9
        }
    }

    private var eyebrowText: String {
        switch scale {
        case .week:      return "Reading · Last 7 days"
        case .month:     return "Reading · Last 30 days"
        case .fourMonth: return "Reading · Last 4 months"
        }
    }

    private var dateRange: String {
        let calendar = Calendar.current
        let start: Date = {
            switch scale {
            case .week:
                return calendar.date(byAdding: .day, value: -6, to: stats.today) ?? stats.today
            case .month:
                return calendar.date(byAdding: .day, value: -29, to: stats.today) ?? stats.today
            case .fourMonth:
                return stats.firstDay
            }
        }()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        let from = f.string(from: start)
        f.dateFormat = "MMM d, yyyy"
        let to = f.string(from: stats.today)
        return "\(from) — \(to)"
    }

    private var parallaxProgress: Double {
        Double(max(0, min(1, scrollOffset / 320)))
    }
    private var heroOpacity: Double {
        1 - pow(parallaxProgress, 1.2)
    }
    private var heroTranslateY: CGFloat {
        -CGFloat(parallaxProgress) * 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: eyebrowText)
                .revealOnAppear(delay: 0.05, y: 12)

            SerifDisplay(text: "Page by quiet\npage.", size: 38)
                .lineSpacing(2)
                .padding(.top, 8)
                .multilineTextAlignment(.leading)
                .revealOnAppear(delay: 0.15, y: 14)

            HStack {
                Spacer(minLength: 0)
                ReadingHeatmapView(
                    model: HeatmapGridModel.build(
                        scale: scale,
                        today: stats.today,
                        firstDay: stats.firstDay,
                        activityByDay: stats.activityByDay
                    ),
                    palette: palette,
                    cellSize: heroCell,
                    gap: heroGap,
                    radius: heroRad,
                    showLabels: true,
                    stagger: false
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 28)

            Text(dateRange)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .tracking(0.4)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 22)
                .revealOnAppear(delay: 0.5, y: 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .opacity(heroOpacity)
        .offset(y: heroTranslateY)
    }
}

// MARK: - Total time

struct TotalTimeSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @State private var visible = false

    private var avgPerDay: Int {
        guard stats.daysTracked > 0 else { return 0 }
        return Int((Double(stats.totalMinutes) / Double(stats.daysTracked)).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "You spent")

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                CountUpText(
                    target: Double(stats.totalMinutes) / 60.0,
                    duration: 1.6,
                    ease: .easeOutQuint,
                    trigger: visible
                ) { value in
                    SerifDisplay(
                        text: value < 10 ? String(format: "%.1f", value) : "\(Int(value))",
                        size: 96,
                        color: palette.accent
                    )
                }
                SerifDisplay(text: "hours", size: 36, color: Color.primary.opacity(0.7))
            }
            .padding(.top, 8)

            Text("listening across \(Text("\(stats.totalSessions) sessions").fontWeight(.semibold).foregroundColor(.primary)) and \(Text("\(stats.activityByDay.count) days").fontWeight(.semibold).foregroundColor(.primary)). That's about \(Text(fmtHoursMins(avgPerDay)).fontWeight(.semibold).foregroundColor(.primary)) every day you've had the app.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 14)
                .revealOnAppear(delay: 0.4, y: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { visible = true }
        }
    }
}

// MARK: - Best day

struct BestDaySection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false

    var body: some View {
        guard let bd = stats.bestDay else {
            return AnyView(EmptyView())
        }
        return AnyView(content(bd))
    }

    @ViewBuilder
    private func content(_ bd: ReadingStats.BestDay) -> some View {
        let dayName: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEEE"
            return f.string(from: bd.date)
        }()
        let lastName: String = bd.topBookAuthor?.split(separator: " ").last.map(String.init) ?? "a book"
        let dateLabel: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, MMMM d"
            return f.string(from: bd.date)
        }()

        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "Your best day", color: palette.accent)

            VStack(alignment: .leading, spacing: 0) {
                SerifDisplay(text: "A long \(dayName)", size: 42)
                Text("with \(lastName).")
                    .font(.system(size: 42, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .kerning(-0.84)
            }
            .padding(.top, 10)

            // Card
            HStack(alignment: .center, spacing: 16) {
                bookCover(title: bd.topBookTitle ?? "Reading session", size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateLabel.uppercased())
                        .font(.system(size: 11))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text(bd.topBookTitle ?? "Reading session")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    CountUpText(target: Double(bd.minutes), duration: 1.4, trigger: visible) { value in
                        SerifDisplay(text: fmtHoursMins(Int(value)), size: 22, weight: .medium)
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                miniGrid(around: bd)
            }
            .padding(16)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            .padding(.top, 24)
            .revealOnAppear(delay: 0.3, y: 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { visible = true }
        }
    }

    @ViewBuilder
    private func bookCover(title: String, size: CGFloat) -> some View {
        // Use the app's generated cover for visual continuity.
        GeneratedCoverView(title: title)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func miniGrid(around bd: ReadingStats.BestDay) -> some View {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: bd.date)
        let mondayOffset = -((weekday + 5) % 7)
        let bestMonday = calendar.date(byAdding: .day, value: mondayOffset, to: bd.date) ?? bd.date
        let start = calendar.date(byAdding: .day, value: -7, to: bestMonday) ?? bestMonday
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { r in
                        let d = calendar.date(byAdding: .day, value: w * 7 + r, to: start) ?? start
                        let k = ReadingSession.makeDayKey(date: d, calendar: calendar)
                        let mins = stats.activityByDay[k]?.minutes ?? 0
                        let isBest = (k == bd.dayKey)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(palette.color(forMinutes: mins, scheme: colorScheme))
                            .frame(width: 7, height: 7)
                            .overlay {
                                if isBest {
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .strokeBorder(colorScheme == .dark ? Color.white : Color.black, lineWidth: 1.2)
                                }
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Best time of day

struct BestTimeSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false

    private var period: String {
        let h = stats.bestHour
        switch h {
        case ..<5:   return "late nights"
        case ..<11:  return "mornings"
        case ..<14:  return "around noon"
        case ..<18:  return "afternoons"
        case ..<21:  return "evenings"
        default:     return "late evenings"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "You read most in the")

            SerifDisplay(text: "\(period).", size: 48)
                .padding(.top, 8)

            Text("Peak hour: \(Text(fmtClock12(stats.bestHour)).fontWeight(.semibold).foregroundColor(.primary))")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            HStack {
                Spacer()
                polarChart
                    .frame(width: 240, height: 240)
                Spacer()
            }
            .padding(.top, 20)
            .revealOnAppear(delay: 0.25, y: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { visible = true }
        }
    }

    private var polarChart: some View {
        let size: CGFloat = 240
        let R: CGFloat = 92
        let r0: CGFloat = 38

        // Treat the dial as a 12-hour analog clock face. Sum AM + PM minutes for
        // each clock position so 2 AM and 2 PM share the "2 o'clock" spoke; the
        // peak-hour text below still calls out the actual hour.
        let clockBuckets: [Int] = (0..<12).map { pos in
            stats.hourMinutes[pos] + stats.hourMinutes[pos + 12]
        }
        let maxH = max(1, clockBuckets.max() ?? 1)
        let bestPos = ((stats.bestHour % 12) + 12) % 12

        return ZStack {
            // Cardinal numerals — 12 top, 3 right, 6 bottom, 9 left
            ForEach([(0, "12"), (3, "3"), (6, "6"), (9, "9")], id: \.0) { pos, label in
                let angle = Angle.degrees(Double(pos) / 12 * 360 - 90)
                Text(label)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(.secondary)
                    .kerning(-0.3)
                    .offset(
                        x: cos(angle.radians) * Double(R + 20),
                        y: sin(angle.radians) * Double(R + 20)
                    )
            }

            // Inner ring
            Circle()
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: 1
                )
                .frame(width: r0 * 2, height: r0 * 2)

            // Spokes — one per clock position (12-hour layout)
            ForEach(0..<12, id: \.self) { pos in
                let angle = Angle.degrees(Double(pos) / 12 * 360 - 90)
                let mins = clockBuckets[pos]
                let len = (Double(mins) / Double(maxH)) * Double(R - r0)
                let isBest = (pos == bestPos)
                Spoke(
                    angleRadians: angle.radians,
                    r0: r0,
                    length: visible ? CGFloat(max(2, len)) : 0
                )
                .stroke(
                    isBest ? palette.accent : (colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)),
                    style: StrokeStyle(lineWidth: isBest ? 5 : 4, lineCap: .round)
                )
                .opacity(isBest ? 1 : 0.55)
                .animation(
                    .interpolatingSpring(stiffness: 80, damping: 14)
                        .delay(Double(pos) * 0.028),
                    value: visible
                )
            }

            // Center
            VStack(spacing: 2) {
                Text("peak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                SerifDisplay(text: fmtClock12(stats.bestHour), size: 20, weight: .medium)
            }
        }
        .frame(width: size, height: size)
    }
}

/// One spoke of the polar chart — a line from r0 outward by `length` along `angleRadians`.
struct Spoke: Shape {
    var angleRadians: Double
    var r0: CGFloat
    var length: CGFloat

    var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let cy = rect.midY
        let x1 = cx + cos(angleRadians) * Double(r0)
        let y1 = cy + sin(angleRadians) * Double(r0)
        let x2 = cx + cos(angleRadians) * Double(r0 + length)
        let y2 = cy + sin(angleRadians) * Double(r0 + length)
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    }
}

// MARK: - Longest book

struct LongestBookSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @State private var visible = false

    var body: some View {
        guard let _ = stats.longestBookID, stats.longestBookMinutes > 0 else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "The book you stayed with")

            VStack(spacing: 16) {
                GeneratedCoverView(title: stats.longestBookTitle ?? "")
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .rotationEffect(.degrees(visible ? -2 : -8))
                    .scaleEffect(visible ? 1 : 0.85)
                    .shadow(color: .black.opacity(visible ? 0.25 : 0.15), radius: visible ? 30 : 8, x: 0, y: visible ? 18 : 4)
                    .animation(.easeOut(duration: 1.4), value: visible)

                VStack(spacing: 4) {
                    SerifDisplay(text: stats.longestBookTitle ?? "", size: 26)
                        .multilineTextAlignment(.center)
                    if let author = stats.longestBookAuthor, !author.isEmpty {
                        Text("by \(author)")
                            .font(.system(size: 13, design: .serif))
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 280)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    CountUpText(target: Double(stats.longestBookMinutes) / 60.0, duration: 1.5, trigger: visible) { value in
                        SerifDisplay(text: String(format: "%.1f", value), size: 56)
                    }
                    Text("hours")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { visible = true }
        }
    }
}

// MARK: - Streak

struct StreakSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false

    private var ribbon: [(active: Bool, minutes: Int)] {
        let calendar = Calendar.current
        var rows: [(Bool, Int)] = []
        for i in (0..<28).reversed() {
            let d = calendar.date(byAdding: .day, value: -i, to: stats.today) ?? stats.today
            let key = ReadingSession.makeDayKey(date: d, calendar: calendar)
            let mins = stats.activityByDay[key]?.minutes ?? 0
            rows.append((mins > 0, mins))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "On a roll")

            HStack(alignment: .lastTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    CountUpText(target: Double(stats.currentStreak), duration: 1.2, trigger: visible) { value in
                        SerifDisplay(text: "\(Int(value.rounded()))", size: 64, color: palette.accent)
                    }
                    Text("day streak")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    CountUpText(target: Double(stats.longestStreak), duration: 1.4, trigger: visible) { value in
                        SerifDisplay(text: "\(Int(value.rounded()))", size: 32)
                    }
                    Text("longest")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("4 weeks ago")
                    Spacer()
                    Text("today")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .tracking(0.4)

                GeometryReader { geo in
                    let count = ribbon.count
                    let totalGap: CGFloat = 3 * CGFloat(count - 1)
                    let barWidth = max(2, (geo.size.width - totalGap) / CGFloat(count))
                    HStack(spacing: 3) {
                        ForEach(Array(ribbon.enumerated()), id: \.offset) { (i, d) in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    d.active
                                        ? palette.color(forMinutes: d.minutes, scheme: colorScheme)
                                        : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                                )
                                .frame(width: barWidth, height: 22)
                                .opacity(visible ? 1 : 0)
                                .offset(y: visible ? 0 : 10)
                                .animation(
                                    .easeOut(duration: 0.6).delay(Double(i) * 0.018),
                                    value: visible
                                )
                        }
                    }
                }
                .frame(height: 22)
            }
            .padding(14)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .padding(.top, 26)
            .revealOnAppear(delay: 0.2, y: 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { visible = true }
        }
    }
}

// MARK: - Metrics trio

struct MetricsTrioSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @State private var visible = false

    private var lastName: String {
        stats.topAuthor?.split(separator: " ").last.map(String.init) ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "The shape of it")

            Group {
                if lastName != "—" {
                    Text("Steady, generous sessions — \(Text("mostly with \(lastName).").italic().foregroundColor(.secondary))")
                } else {
                    Text("Steady, generous sessions")
                }
            }
            .font(.system(size: 32, weight: .semibold, design: .serif))
            .foregroundStyle(.primary)
            .kerning(-0.64)
            .lineSpacing(2)
            .padding(.top, 10)
            .revealOnAppear(delay: 0.1, y: 16)

            HStack(spacing: 10) {
                metricCard(
                    eyebrow: "Avg session",
                    big: "\(Int(stats.avgSession.rounded()))",
                    sub: "min",
                    delay: 0
                )
                metricCard(
                    eyebrow: "Finished",
                    big: "\(stats.booksFinished)",
                    sub: "books",
                    delay: 0.15
                )
                metricCard(
                    eyebrow: "Top author",
                    big: lastName,
                    sub: nil,
                    delay: 0.3
                )
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { visible = true }
        }
    }

    private func metricCard(eyebrow: String, big: String, sub: String?, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(big)
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .kerning(-0.64)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let sub {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 92, alignment: .topLeading)
        .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 20)
        .animation(.easeOut(duration: 0.9).delay(delay), value: visible)
    }
}

// MARK: - Free books

struct FreeBooksSection: View {
    let stats: ReadingStats
    var palette: HeatmapPalette = .amber
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false

    private var pctTarget: Double { stats.freePct * 100 }
    private var hoursTarget: Double { Double(stats.freeMinutes) / 60.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsEyebrow(text: "Public domain, private joy")

            HStack(alignment: .center, spacing: 22) {
                ring
                    .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 6) {
                    CountUpText(target: hoursTarget, duration: 1.5, trigger: visible) { value in
                        let mins = Int((value * 60).rounded())
                        SerifDisplay(text: fmtHoursMins(mins), size: 22)
                    }
                    Text("of your listening was from \(Text("free, public-domain").fontWeight(.semibold).foregroundColor(.primary)) recordings.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .revealOnAppear(delay: 0.1, y: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { visible = true }
        }
    }

    private var ring: some View {
        let stroke: CGFloat = 10
        return ZStack {
            Circle()
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                    lineWidth: stroke
                )
            Circle()
                .trim(from: 0, to: visible ? CGFloat(stats.freePct) : 0)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.5), value: visible)

            CountUpText(target: pctTarget, duration: 1.4, trigger: visible) { value in
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .kerning(-0.56)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Footer

struct StatsFooter: View {
    var onClose: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("The unread copy of every great\nbook is still a great book.")
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .revealOnAppear()

            Button(action: onClose) {
                Text("Back to Library")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .revealOnAppear(delay: 0.12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 56)
    }
}
