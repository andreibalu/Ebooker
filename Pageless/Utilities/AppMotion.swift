import SwiftUI

enum AppMotion {
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let stateChange = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20)
    static let reducedStateChange = Animation.easeOut(duration: 0.20)

    static func stateChangeAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedStateChange : stateChange
    }

    static func stateTransition(
        reduceMotion: Bool,
        anchor: UnitPoint = .top
    ) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: anchor)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: anchor))
        )
    }
}
