//
//  OnboardingScenes.swift
//  Pageless
//
//  The six full-screen scenes of the welcome flow and their widgets.
//  Native rebuild of the prototype's `onboarding-scenes.jsx`. Preference controls bind
//  live to the app's existing @AppStorage keys (passed in as Bindings from the host), so
//  persistence, reversibility, and the scene-6 summary all share one source of truth.
//

import SwiftUI

// MARK: - Choice model

enum OnboardingChoice: String {
    case free
    case own
}

// MARK: - Display helpers

private func resumeShort(_ option: ResumeBacktrackOption) -> String {
    switch option {
    case .exact:          "Exact"
    case .fifteenSeconds: "15s"
    case .thirtySeconds:  "30s"
    case .oneMinute:      "1 min"
    }
}

private func skipShort(_ value: Double) -> String { "\(Int(value))s" }

private func momentStepperLabel(_ option: MomentBacktrackOption) -> String {
    switch option {
    case .exact:          "At the moment"
    case .fifteenSeconds: "15s earlier"
    case .thirtySeconds:  "30s earlier"
    case .oneMinute:      "1 min earlier"
    case .twoMinutes:     "2 min earlier"
    }
}

// MARK: - Scene shell

/// Full-viewport panel: fixed 402pt content column (centered on wider screens), top/edge padding,
/// optional radial accent tint near the top, and gentle parallax drift away from center.
struct OBSceneShell<Content: View>: View {
    var tint: Bool = false
    /// Centers content both horizontally and vertically (used by the Done scene).
    var centered: Bool = false
    /// Centers content vertically only, keeping the default left alignment. Use for short scenes
    /// that otherwise hug the top.
    var verticalCenter: Bool = false
    let reduceMotion: Bool
    @ViewBuilder let content: () -> Content

    private var addSpacers: Bool { centered || verticalCenter }

    var body: some View {
        ZStack(alignment: .top) {
            if tint {
                RadialGradient(
                    colors: [OB.accentSoft, .clear],
                    center: UnitPoint(x: 0.5, y: 0.14),
                    startRadius: 0,
                    endRadius: 340
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }

            VStack(alignment: centered ? .center : .leading, spacing: 0) {
                if addSpacers { Spacer(minLength: 0) }
                content()
                if addSpacers { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, 26)
            .padding(.top, 64)
            .padding(.bottom, 52)
            .frame(maxWidth: 402)
            .frame(maxWidth: .infinity, alignment: .center)
            .obParallax(reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Scene 1 · Choice

struct OBChoiceScene: View {
    let isActive: Bool
    let reduceMotion: Bool
    @Binding var choice: OnboardingChoice?
    let onPicked: () -> Void

    private func pick(_ value: OnboardingChoice) {
        if choice == value {
            // Re-tapping the selected card clears it (Requirement B: reversible).
            withAnimation(OBMotion.settle) { choice = nil }
        } else {
            withAnimation(OBMotion.settle) { choice = value }
            // Advance to the playback scene after the selection animation settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { onPicked() }
        }
    }

    var body: some View {
        OBSceneShell(tint: true, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 0) {
                // Brand mark
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(OB.accent)
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "book.pages.fill").font(.system(size: 13)).foregroundStyle(.white))
                    Text("Unpaged")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(OB.label)
                }
                .padding(.bottom, 22)

                OBEyebrow(text: choice == nil ? "Welcome" : "Got it")
                OBHeadline(text: headline, size: 31)
                    .padding(.top, 10)
                OBSub(text: choice == nil
                      ? "Pick one — this sets your home tab. You can change it later."
                      : "You can switch anytime in your library.")
                    .padding(.top, 9)

                VStack(spacing: 14) {
                    choiceCard(.free, icon: "books.vertical.fill", title: "Free books",
                               desc: "Thousands of public-domain audiobooks, ready to play.",
                               tag: "No import needed")
                    choiceCard(.own, icon: "arrow.down.circle", title: "My books",
                               desc: "Bring audiobooks you already own. Import from Files.",
                               tag: "Your own library")
                }
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(choice == nil ? "Scroll to continue" : "Setting up your playback…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(OB.tertiary)
                    OBBounceChevron(reduceMotion: reduceMotion)
                }
                .frame(maxWidth: .infinity)
                .opacity(choice == nil ? 0.55 : 1)
                .padding(.top, 26)
            }
            .obReveal(active: isActive)
        }
    }

    private var headline: String {
        switch choice {
        case .free: "Starting with free books."
        case .own:  "Starting with your books."
        case nil:   "How do you want to start?"
        }
    }

    private func choiceCard(_ id: OnboardingChoice, icon: String, title: String, desc: String, tag: String) -> some View {
        let selected = choice == id
        return Button {
            pick(id)
        } label: {
            HStack(spacing: 15) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected ? OB.accent : OB.accentSoft)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundStyle(selected ? Color.white : OB.accent)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 19, weight: .bold))
                            .tracking(-0.38)
                            .foregroundStyle(OB.label)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(OB.accent))
                        }
                    }
                    Text(desc)
                        .font(.system(size: 13.5))
                        .foregroundStyle(OB.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OB.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(OB.accentSoft))
                        .padding(.top, 9)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.cardWhite)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(OB.accent, lineWidth: selected ? 2 : 0)
            )
            .shadow(color: selected ? OB.accent.opacity(0.22) : .black.opacity(0.07),
                    radius: selected ? 17 : 7, y: selected ? 14 : 4)
            .scaleEffect(selected ? 1.025 : 1)
        }
        .buttonStyle(.plain)
    }
}

private struct OBBounceChevron: View {
    let reduceMotion: Bool
    @State private var down = false
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(OB.tertiary)
            .offset(y: down ? 5 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    down = true
                }
            }
    }
}

// MARK: - Scene 2 · Playback

struct OBPlaybackScene: View {
    let isActive: Bool
    let reduceMotion: Bool
    @Binding var resume: Double
    @Binding var skipBack: Double
    @Binding var skipForward: Double
    @Binding var moment: Double

    var body: some View {
        OBSceneShell(reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    OBEyebrow(text: "Playback")
                    OBHeadline(text: "Set up listening.", size: 30).padding(.top, 10)
                    OBSub(text: "Three quick choices. The defaults are good too.").padding(.top, 9)
                }
                .obReveal(active: isActive)

                VStack(spacing: 14) {
                    prefBlock(icon: "play.circle", title: "On resume",
                              caption: "Rewind a little when you press play after a break.",
                              delay: 0.08) {
                        OBResumeSlider(selection: $resume, reduceMotion: reduceMotion)
                    }

                    prefBlock(icon: "gobackward.30", title: "Skip buttons",
                              caption: "How far the back and forward buttons jump.",
                              delay: 0.16) {
                        VStack(spacing: 10) {
                            OBChipRow(value: $skipBack, leadingSymbol: "gobackward.30")
                            OBChipRow(value: $skipForward, leadingSymbol: "goforward.30")
                        }
                    }

                    prefBlock(icon: "bookmark.fill", title: "Save moment offset",
                              caption: "Where a saved moment lands relative to now.",
                              delay: 0.24) {
                        OBStepper(value: $moment)
                    }
                }
                .padding(.top, 22)
            }
        }
    }

    private func prefBlock<Content: View>(
        icon: String, title: String, caption: String, delay: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(OB.accent)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .tracking(-0.32)
                    .foregroundStyle(OB.label)
            }
            .padding(.bottom, 4)
            Text(caption)
                .font(.system(size: 12.5))
                .foregroundStyle(OB.secondary)
                .padding(.bottom, 15)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.cardWhite))
        .shadow(color: .black.opacity(0.06), radius: 7, y: 4)
        .obReveal(active: isActive, delay: delay)
    }
}

/// Resume-rewind amount as a magnetic snap slider. Four stops (Exact → 1 min); the thumb locks to
/// the nearest stop as you drag — no free glide to fight, no value to "land" — and the whole track
/// is tappable. The amber fill is the rewind amount: more fill = more rewind. The serif value above
/// updates live so it doubles as a readout while dragging.
private struct OBResumeSlider: View {
    @Binding var selection: Double
    let reduceMotion: Bool

    private let options = ResumeBacktrackOption.allCases   // .exact, 15s, 30s, 1 min (left → right)
    private let inset: CGFloat = 17           // half the thumb — keeps the thumb fully on-track at the ends
    private let thumbSize: CGFloat = 34
    private let trackHeight: CGFloat = 8

    /// Live stop while dragging; falls back to the committed selection when idle.
    @State private var dragIndex: Int? = nil
    @State private var lastHaptic = -1
    private let haptics = UISelectionFeedbackGenerator()

    private var index: Int {
        options.firstIndex(where: { $0.rawValue == selection }) ?? options.count - 1
    }
    private var liveIndex: Int { dragIndex ?? index }

    var body: some View {
        VStack(spacing: 15) {
            obSerif(resumeShort(options[liveIndex]), size: 40, color: OB.accent)

            GeometryReader { geo in
                let w = geo.size.width
                let span = max(1, w - inset * 2)
                let midY = thumbSize / 2
                let x: (Int) -> CGFloat = { i in inset + span * CGFloat(i) / CGFloat(options.count - 1) }
                let thumbX = x(liveIndex)

                ZStack {
                    // Base track (runs between the first and last stops)
                    Capsule()
                        .fill(OB.fill(0.08))
                        .frame(width: span, height: trackHeight)
                        .position(x: w / 2, y: midY)

                    // Amber fill from the first stop up to the thumb
                    Capsule()
                        .fill(OB.accent)
                        .frame(width: max(0, thumbX - inset), height: trackHeight)
                        .position(x: inset + max(0, thumbX - inset) / 2, y: midY)

                    // Stop dots — white once the fill has passed them, faint otherwise
                    ForEach(options.indices, id: \.self) { i in
                        Circle()
                            .fill(i <= liveIndex ? Color.white.opacity(0.9) : OB.fill(0.22))
                            .frame(width: 5, height: 5)
                            .position(x: x(i), y: midY)
                    }

                    // Thumb
                    Circle()
                        .fill(Color.cardWhite)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().strokeBorder(OB.accent, lineWidth: 2.5))
                        .overlay(Circle().fill(OB.accent).frame(width: 12, height: 12))
                        .shadow(color: OB.accent.opacity(0.3), radius: 6, y: 3)
                        .position(x: thumbX, y: midY)
                }
                .frame(width: w, height: thumbSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in update(toX: v.location.x, span: span) }
                        .onEnded { _ in commit() }
                )
            }
            .frame(height: thumbSize)

            // Stop labels, aligned under each dot
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    Text(resumeShort(options[i]))
                        .font(.system(size: 11.5, weight: i == liveIndex ? .bold : .semibold))
                        .foregroundStyle(i == liveIndex ? OB.accent : OB.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { haptics.prepare() }
    }

    /// Nearest stop to a touch x within the track span.
    private func nearestIndex(toX px: CGFloat, span: CGFloat) -> Int {
        let frac = (px - inset) / span
        let raw = frac * CGFloat(options.count - 1)
        return max(0, min(options.count - 1, Int(raw.rounded())))
    }

    private func update(toX px: CGFloat, span: CGFloat) {
        let i = nearestIndex(toX: px, span: span)
        if i != lastHaptic {
            lastHaptic = i
            if !reduceMotion { haptics.selectionChanged() }
        }
        guard i != dragIndex else { return }
        if reduceMotion {
            dragIndex = i
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { dragIndex = i }
        }
    }

    private func commit() {
        let target = dragIndex ?? index
        lastHaptic = -1
        if reduceMotion {
            selection = options[target].rawValue
            dragIndex = nil
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                selection = options[target].rawValue
                dragIndex = nil
            }
        }
    }
}

/// Three equal chips (15s / 30s / 45s) led by a skip glyph.
private struct OBChipRow: View {
    @Binding var value: Double
    let leadingSymbol: String
    private let options = SkipIntervalOption.allCases

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 20))
                .foregroundStyle(OB.secondary)
                .frame(width: 30)
            ForEach(options) { option in
                let on = option.rawValue == value
                Button {
                    withAnimation(OBMotion.settle) { value = option.rawValue }
                } label: {
                    Text(skipShort(option.rawValue))
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.14)
                        .foregroundStyle(on ? Color.white : OB.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(on ? OB.accent : OB.fill(0.06))
                        )
                        .shadow(color: on ? OB.accent.opacity(0.28) : .clear, radius: 8, y: 6)
                        .offset(y: on ? -1 : 0)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// − / value / + stepper across the moment-offset options.
private struct OBStepper: View {
    @Binding var value: Double
    private let options = MomentBacktrackOption.allCases

    private var index: Int { options.firstIndex(where: { $0.rawValue == value }) ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            stepButton("minus", disabled: index <= 0) {
                set(index - 1)
            }
            Text(momentStepperLabel(options[index]))
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.17)
                .foregroundStyle(OB.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OB.accentSoft))
            stepButton("plus", disabled: index >= options.count - 1) {
                set(index + 1)
            }
        }
    }

    private func set(_ newIndex: Int) {
        let clamped = max(0, min(options.count - 1, newIndex))
        withAnimation(OBMotion.settle) { value = options[clamped].rawValue }
    }

    private func stepButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(disabled ? OB.tertiary : OB.label)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OB.fill(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Scene 3 · Stats

struct OBStatsScene: View {
    let isActive: Bool
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OBSceneShell(tint: true, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    HStack(spacing: 8) {
                        OBEyebrow(text: "If you stick with it")
                        Text("A sample year")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(OB.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(OB.fill(0.06)))
                    }
                    OBHeadline(text: "Imagine your year.", size: 32).padding(.top, 10)
                    OBSub(text: "Unpaged keeps count, quietly. Here's what a year can look like.").padding(.top, 9)
                }
                .obReveal(active: isActive)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if reduceMotion {
                        // Reduce Motion: show the final figure immediately, no count-up.
                        obSerif("127", size: 92, color: OB.accent)
                    } else {
                        CountUpText(target: 127, duration: 1.7, ease: .easeOutQuint, trigger: isActive) { value in
                            obSerif("\(Int(value))", size: 92, color: OB.accent)
                        }
                    }
                    obSerif("hours", size: 30).opacity(0.75)
                }
                .padding(.top, 26)

                (Text("across ").foregroundColor(OB.secondary)
                 + Text("240 sessions").foregroundColor(OB.label).fontWeight(.semibold)
                 + Text(" and ").foregroundColor(OB.secondary)
                 + Text("168 days").foregroundColor(OB.label).fontWeight(.semibold)
                 + Text(".").foregroundColor(OB.secondary))
                    .font(.system(size: 15.5))
                    .padding(.top, 6)
                    .obReveal(active: isActive, delay: 0.2)

                VStack(spacing: 12) {
                    OBHeatmap(active: isActive, reduceMotion: reduceMotion, dark: colorScheme == .dark)
                    HStack {
                        ForEach(["JAN", "APR", "JUL", "OCT", "DEC"], id: \.self) { label in
                            Text(label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(OB.tertiary)
                            if label != "DEC" { Spacer() }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.cardWhite))
                .shadow(color: .black.opacity(0.06), radius: 7, y: 4)
                .padding(.top, 26)
                .obReveal(active: isActive, delay: 0.12)

                HStack(spacing: 10) {
                    metric("34", sub: "d", label: "Best streak", delay: 0.08)
                    metric("9", sub: nil, label: "Books done", delay: 0.18)
                    metric("9", sub: "PM", label: "Peak hour", delay: 0.28)
                }
                .padding(.top, 14)
            }
        }
    }

    private func metric(_ big: String, sub: String?, label: String, delay: Double) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                obSerif(big, size: 26)
                if let sub {
                    Text(sub).font(.system(size: 11, weight: .semibold)).foregroundStyle(OB.secondary)
                }
            }
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(OB.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.cardWhite))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
        .obReveal(active: isActive, delay: delay)
    }
}

private struct OBHeatmap: View {
    let active: Bool
    let reduceMotion: Bool
    let dark: Bool

    private let weeks = 17
    private let days = 7
    private let levels: [Int] = OBHeatmap.makeLevels(seed: 99, count: 17 * 7)
    @State private var revealed = false

    static func makeLevels(seed: UInt32, count: Int) -> [Int] {
        var s = seed
        var out: [Int] = []
        for _ in 0..<count {
            s = s &* 1664525 &+ 1013904223
            let r = Double(s) / 4294967296.0
            out.append(r < 0.18 ? 0 : r < 0.42 ? 1 : r < 0.68 ? 2 : r < 0.88 ? 3 : 4)
        }
        return out
    }

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<weeks, id: \.self) { wi in
                VStack(spacing: 3.5) {
                    ForEach(0..<days, id: \.self) { di in
                        let level = levels[wi * days + di]
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(revealed ? OB.heat(level, dark: dark)
                                  : (dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
                            .frame(width: 13, height: 13)
                            .scaleEffect(revealed ? 1 : 0.4)
                            .opacity(revealed ? 1 : 0)
                            .animation(reduceMotion ? nil
                                       : OBMotion.settle.delay(Double(wi + di) * 0.011),
                                       value: revealed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if active { revealed = true } }
        .onChange(of: active) { _, isActive in if isActive { revealed = true } }
    }
}

// MARK: - Scene 4 · Apple Intelligence

struct OBIntelligenceScene: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        OBSceneShell(verticalCenter: true, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(OB.accent)
                        OBEyebrow(text: "Apple Intelligence")
                    }
                    OBHeadline(text: "Moments, named for you.", size: 30).padding(.top, 10)
                    OBSub(text: "Save a spot and Unpaged suggests a title from what you just heard.").padding(.top, 9)
                }
                .obReveal(active: isActive)

                OBMomentNameCard(active: isActive, reduceMotion: reduceMotion)
                    .padding(.top, 22)
                    .obReveal(active: isActive, delay: 0.14)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.left").font(.system(size: 14)).foregroundStyle(OB.accent)
                        Text("Pick up where you left off")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(OB.label)
                    }
                    Text("You left off as Bingley settles at Netherfield and Mrs. Bennet plans the Meryton ball.")
                        .font(.system(size: 14))
                        .foregroundStyle(OB.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(OB.accentSoft).frame(width: 2)
                        }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.cardWhite))
                .shadow(color: .black.opacity(0.06), radius: 7, y: 4)
                .padding(.top, 14)
                .obReveal(active: isActive, delay: 0.22)

                HStack(spacing: 8) {
                    Image(systemName: "internaldrive").font(.system(size: 13)).foregroundStyle(OB.tertiary)
                    Text("Runs on your device. Nothing leaves your phone.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(OB.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .obReveal(active: isActive, delay: 0.3)
            }
        }
    }
}

private struct OBMomentNameCard: View {
    let active: Bool
    let reduceMotion: Bool
    @State private var named = false

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "7B6CE5"), Color(hex: "3B2E9E")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 46, height: 58)
                .overlay(
                    Text("P")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.92))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("SAVED MOMENT · 1:24:07")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(OB.secondary)
                ZStack(alignment: .leading) {
                    Text("Untitled moment")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(OB.tertiary)
                        .opacity(named ? 0 : 1)
                        .offset(y: named ? -8 : 0)
                    Text("First impression of Mr. Darcy")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.16)
                        .foregroundStyle(OB.label)
                        .lineLimit(1)
                        .opacity(named ? 1 : 0)
                        .offset(y: named ? 0 : 8)
                }
                .frame(height: 22, alignment: .leading)
                .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(named ? OB.accent : OB.tertiary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(named ? OB.accentSoft : OB.fill(0.06)))
                .scaleEffect(named ? 1 : 0.8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.cardWhite))
        .shadow(color: .black.opacity(0.06), radius: 7, y: 4)
        .onChange(of: active) { _, isActive in if isActive { schedule() } }
        .onAppear { if active { schedule() } }
    }

    private func schedule() {
        guard !named else { return }
        if reduceMotion {
            named = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(OBMotion.settle) { named = true }
        }
    }
}

// MARK: - Scene 5 · iCloud sync

struct OBCloudScene: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        OBSceneShell(tint: true, verticalCenter: true, reduceMotion: reduceMotion) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    HStack(spacing: 7) {
                        Image(systemName: "icloud.fill").font(.system(size: 15)).foregroundStyle(OB.accent)
                        OBEyebrow(text: "iCloud Sync")
                    }
                    OBHeadline(text: "Everything in sync.", size: 31).padding(.top, 10)
                    OBSub(text: "Pick up on any device, right where you stopped.").padding(.top, 9)
                }
                .obReveal(active: isActive)

                OBSyncGraphic(active: isActive, reduceMotion: reduceMotion)
                    .padding(.top, 24)
                    .padding(.bottom, 26)
                    .obReveal(active: isActive, delay: 0.12)

                VStack(alignment: .leading, spacing: 14) {
                    benefitRow("play.circle", "Progress, moments and history stay in sync.", delay: 0.18)
                    benefitRow("internaldrive", "Audio files stay on each device.", delay: 0.26)
                    benefitRow("icloud", "Private — through your own iCloud account.", delay: 0.34)
                }
            }
        }
    }

    private func benefitRow(_ symbol: String, _ text: String, delay: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(OB.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(OB.accentSoft))
            Text(text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(OB.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .obReveal(active: isActive, delay: delay)
    }
}

/// Three device glyphs across the top, a central pulsing iCloud badge, dotted accent connectors.
/// Requirement C: captions sit *above* each glyph and connectors run from the glyph's bottom edge
/// down to the cloud, so a line never crosses a device box or its caption.
private struct OBSyncGraphic: View {
    let active: Bool
    let reduceMotion: Bool

    private let canvasW: CGFloat = 360
    private let canvasH: CGFloat = 168

    // Device glyph centers and box sizes. Tops aligned so all captions share one row above them.
    private struct Device { let center: CGPoint; let size: CGSize; let cornerRadius: CGFloat; let label: String }
    private var devices: [Device] {
        let topY: CGFloat = 30
        return [
            Device(center: CGPoint(x: 56, y: topY + 23), size: CGSize(width: 30, height: 46), cornerRadius: 7, label: "iPhone"),
            Device(center: CGPoint(x: canvasW / 2, y: topY + 19), size: CGSize(width: 52, height: 38), cornerRadius: 6, label: "iPad"),
            Device(center: CGPoint(x: canvasW - 56, y: topY + 19), size: CGSize(width: 60, height: 38), cornerRadius: 6, label: "Mac")
        ]
    }
    private var cloudCenter: CGPoint { CGPoint(x: canvasW / 2, y: 122) }

    @State private var pulse = false
    @State private var drawn = false

    var body: some View {
        ZStack {
            // Dotted connectors — run from the cloud up to the bottom edge of each device box
            // (+ small gap). Captions live above the boxes, so a line never reaches a label.
            ForEach(devices.indices, id: \.self) { i in
                let d = devices[i]
                let end = CGPoint(x: d.center.x, y: d.center.y + d.size.height / 2 + 6)
                Path { p in
                    p.move(to: cloudCenter)
                    p.addLine(to: end)
                }
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(OB.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 6]))
            }

            // Device glyphs — box centered at `d.center`; caption placed *above* the box so neither
            // the box nor the label sits on the downward connector path.
            ForEach(devices.indices, id: \.self) { i in
                let d = devices[i]
                RoundedRectangle(cornerRadius: d.cornerRadius, style: .continuous)
                    .fill(Color.cardWhite)
                    .frame(width: d.size.width, height: d.size.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: d.cornerRadius, style: .continuous)
                            .strokeBorder(OB.fill(0.10), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                    .position(d.center)
                    .opacity(drawn ? 1 : 0)

                Text(d.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OB.tertiary)
                    .position(x: d.center.x, y: d.center.y - d.size.height / 2 - 11)
                    .opacity(drawn ? 1 : 0)
            }

            // Central cloud badge
            ZStack {
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(OB.accent.opacity(0.4), lineWidth: 2)
                        .frame(width: 76, height: 76)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(pulse ? 0 : 0.5)
                }
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(OB.accent)
                    .frame(width: 76, height: 76)
                    .overlay(Image(systemName: "icloud.fill").font(.system(size: 34)).foregroundStyle(.white))
                    .shadow(color: OB.accent.opacity(0.4), radius: 15, y: 12)
            }
            .position(cloudCenter)
            .scaleEffect(drawn ? 1 : 0.7)
            .opacity(drawn ? 1 : 0)
        }
        .frame(width: canvasW, height: canvasH)
        .frame(maxWidth: .infinity)
        .onAppear { if active { start() } }
        .onChange(of: active) { _, isActive in if isActive { start() } }
    }

    private func start() {
        if reduceMotion {
            drawn = true
            return
        }
        withAnimation(OBMotion.reveal()) { drawn = true }
        withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) { pulse = true }
    }
}

// MARK: - Scene 6 · Done

struct OBDoneScene: View {
    let isActive: Bool
    let reduceMotion: Bool
    let choice: OnboardingChoice?
    let resume: Double
    let skipBack: Double
    let skipForward: Double
    let moment: Double
    let onOpen: () -> Void

    @State private var popped = false

    var body: some View {
        OBSceneShell(tint: true, centered: true, reduceMotion: reduceMotion) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(OB.accent)
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white))
                    .shadow(color: OB.accent.opacity(0.4), radius: 18, y: 16)
                    .scaleEffect(popped ? 1 : 0.5)
                    .opacity(popped ? 1 : 0)

                OBHeadline(text: "You're all set.", size: 34).padding(.top, 22)

                (Text("Starting with ").foregroundColor(OB.secondary)
                 + Text(choice == .own ? "your books" : "free books").foregroundColor(OB.label).fontWeight(.semibold)
                 + Text(". Adjust anything in Settings whenever you like.").foregroundColor(OB.secondary))
                    .font(.system(size: 15.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
                    .padding(.top, 10)

                summaryCard.padding(.top, 22)

                Button(action: onOpen) {
                    Text("Open Library")
                        .font(.system(size: 16.5, weight: .bold))
                        .tracking(-0.16)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OB.accent))
                        .shadow(color: OB.accent.opacity(0.36), radius: 13, y: 10)
                }
                .buttonStyle(OBPressButtonStyle())
                .frame(maxWidth: 320)
                .padding(.top, 24)

                Text("Takes you straight to your books.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OB.tertiary)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .onAppear { if isActive { pop() } }
            .onChange(of: isActive) { _, active in if active { pop() } }
        }
    }

    private func pop() {
        guard !popped else { return }
        if reduceMotion { popped = true } else {
            withAnimation(OBMotion.settle) { popped = true }
        }
    }

    private var summaryCard: some View {
        let rows: [(String, String)] = [
            ("Home tab", choice == .own ? "My books" : "Free books"),
            ("On resume", resumeShort(ResumeBacktrackOption(rawValue: resume) ?? .oneMinute)),
            ("Skip", "\(skipShort(skipBack)) / \(skipShort(skipForward))"),
            ("Moment offset", momentStepperLabel(MomentBacktrackOption(rawValue: moment) ?? .exact).lowercased())
        ]
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0).font(.system(size: 13.5)).foregroundStyle(OB.secondary)
                    Spacer()
                    Text(rows[i].1).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(OB.label)
                }
                .padding(.vertical, 11)
                if i < rows.count - 1 {
                    Rectangle().fill(OB.separator).frame(height: 0.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 320)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.cardWhite))
        .shadow(color: .black.opacity(0.06), radius: 7, y: 4)
    }
}

private struct OBPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(OBMotion.settle, value: configuration.isPressed)
    }
}
