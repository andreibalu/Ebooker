//
//  AppAppearance.swift
//  Pageless
//
//  The user's Appearance choice (System / Light / Dark) and how it reaches the screen.
//
//  It is applied as `overrideUserInterfaceStyle` on the scene's windows rather than through
//  `.preferredColorScheme`: the old `forceDarkMode ? .dark : nil` mapping meant "off" followed the
//  system (so the toggle did nothing on a dark phone), and SwiftUI does not restore the system
//  scheme after `.dark` → `nil` until relaunch. A window override reaches every sheet and
//  full-screen cover and reverts cleanly to `.unspecified`.
//

import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"
    /// Pre-1.5 boolean toggle. `true` migrates to `.dark`; `false` to `.system`.
    static let legacyDarkModeKey = "forceDarkMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Writes the new key from the legacy toggle once. Safe to call on every launch.
    static func migrateLegacyPreference(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil else { return }
        if defaults.bool(forKey: legacyDarkModeKey) {
            defaults.set(AppAppearance.dark.rawValue, forKey: storageKey)
        }
    }
}

extension View {
    /// Applies the Appearance choice to the hosting window scene. Attach once, at the app root.
    func appAppearance(_ appearance: AppAppearance) -> some View {
        background(WindowAppearanceApplier(style: appearance.interfaceStyle).frame(width: 0, height: 0))
    }
}

private struct WindowAppearanceApplier: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> ApplierView {
        let view = ApplierView()
        view.style = style
        return view
    }

    func updateUIView(_ view: ApplierView, context: Context) {
        view.style = style
    }

    final class ApplierView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            // Every window in the scene, so anything UIKit puts in a separate window follows too.
            let windows = window.windowScene?.windows ?? [window]
            for window in windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
