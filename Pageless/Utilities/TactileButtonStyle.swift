//
//  TactileButtonStyle.swift
//  Pageless
//

import SwiftUI

/// Subtle press scale for custom-surface buttons, keeping plain hit geometry (safe with
/// Button Shapes) and respecting Reduce Motion by falling back to opacity only.
struct TactileScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
