//
//  OnboardingTheme.swift
//  Pageless
//
//  Design tokens, type primitives, and motion helpers for the welcome onboarding flow.
//  Mirrors the prototype's `onboarding-core.jsx`. Colors reuse the app's existing dynamic
//  theme where they already match (`Color.cream`, `.cardWhite`, `.amber`) and add the
//  remaining tokens here so the flow reads identically in light and dark.
//

import SwiftUI

// MARK: - Color tokens

enum OB {
    /// Accent — matches `Color.amber` (#CC8632 light / #E59A19 dark). Aliased for readability.
    static let accent = Color.amber

    /// Faint accent tint used for glows, icon tiles, chips and inner rules.
    static let accentSoft = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.898, green: 0.604, blue: 0.098, alpha: 0.16)
            : UIColor(red: 0.800, green: 0.525, blue: 0.196, alpha: 0.12)
    })

    /// Primary text — pure black / white, matching the prototype's `label`.
    static let label = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    })

    static let secondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 235/255, green: 235/255, blue: 245/255, alpha: 0.6)
            : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.6)
    })

    static let tertiary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 235/255, green: 235/255, blue: 245/255, alpha: 0.3)
            : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.3)
    })

    static let separator = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 84/255, green: 84/255, blue: 88/255, alpha: 0.6)
            : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.16)
    })

    /// Generic black-on-light / white-on-dark overlay at a given alpha (the prototype's p04–p25).
    static func fill(_ alpha: Double) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: alpha)
                : UIColor(white: 0, alpha: alpha)
        })
    }

    /// 5-step heatmap ramp (low → high) for the sample-year contribution grid.
    /// Uses the shared `Color(hex:)` initializer defined alongside the Reading Stats heatmap.
    static func heat(_ level: Int, dark: Bool) -> Color {
        let light = ["ECE4D2", "F3D9A8", "E8B36C", "CC8632", "995510"]
        let dk = ["2A2722", "4A3C26", "7B5C2A", "B07A1F", "E59A19"]
        let idx = max(0, min(4, level))
        return Color(hex: dark ? dk[idx] : light[idx])
    }
}

// MARK: - Motion

enum OBMotion {
    /// Immediate press feedback — cubic-bezier(0.23, 1, 0.32, 1).
    static let press = AppMotion.press
    /// Direct selection feedback — cubic-bezier(0.23, 1, 0.32, 1).
    static let selection = AppMotion.stateChange
    /// Gentle settle — cubic-bezier(0.22, 1, 0.36, 1).
    static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.62)
    /// Expo-out reveal — cubic-bezier(0.16, 1, 0.3, 1).
    static func reveal(_ duration: Double = 0.9) -> Animation {
        Animation.timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }
}

// MARK: - Type primitives

/// Uppercase accent eyebrow (11.5pt / 700 / +0.13em tracking).
struct OBEyebrow: View {
    let text: String
    var color: Color = OB.accent
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .bold))
            .tracking(11.5 * 0.13)
            .foregroundStyle(color)
    }
}

/// Tight sans headline (sentence case, ends in a period). Weight ≈ heavy, −0.025em tracking.
struct OBHeadline: View {
    let text: String
    var size: CGFloat = 30
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(size * -0.025)
            .foregroundStyle(OB.label)
            .lineSpacing(size * 0.08 * 0.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Secondary body copy (15.5pt / ~450 / line-height 1.45).
struct OBSub: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15.5, weight: .regular))
            .foregroundStyle(OB.secondary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// System-serif (New York) tabular number used for hero figures, ruler values and metric tiles.
func obSerif(_ string: String, size: CGFloat, color: Color = OB.label) -> Text {
    Text(string)
        .font(.system(size: size, weight: .medium, design: .serif))
        .tracking(size * -0.02)
        .monospacedDigit()
        .foregroundColor(color)
}

// MARK: - Reveal

/// Fade + rise reveal that fires when its scene becomes active (not merely on appear, since a
/// paged ScrollView instantiates rows before they center). One-shot; honors Reduce Motion.
private struct OBRevealModifier: ViewModifier {
    let active: Bool
    var delay: Double = 0
    var y: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : y)
            .onAppear { if active { trigger() } }
            .onChange(of: active) { _, isActive in if isActive { trigger() } }
    }

    private func trigger() {
        guard !shown else { return }
        if reduceMotion {
            shown = true
        } else {
            withAnimation(OBMotion.reveal().delay(delay)) { shown = true }
        }
    }
}

extension View {
    /// Reveals content with a fade + rise once `active` becomes true, after `delay` seconds.
    func obReveal(active: Bool, delay: Double = 0, y: CGFloat = 22) -> some View {
        modifier(OBRevealModifier(active: active, delay: delay, y: y))
    }

    /// Subtle vertical parallax + fade as the scene drifts away from viewport center.
    /// No-op under Reduce Motion. Uses `.visualEffect` so it never affects layout.
    func obParallax(reduceMotion: Bool) -> some View {
        let screenHeight = UIScreen.main.bounds.height
        return visualEffect { content, proxy in
            let mid = proxy.frame(in: .global).midY
            let vh = max(proxy.size.height, 1)
            // 0 at center, ±1 toward the edges of the viewport.
            let edge = max(-1, min(1, (mid - screenHeight / 2) / vh * 2))
            let drift = reduceMotion ? 0 : edge * 22
            let fade = reduceMotion ? 1 : 1 - min(1, abs(edge) * 0.85) * 0.55
            return content.offset(y: drift).opacity(fade)
        }
    }
}
