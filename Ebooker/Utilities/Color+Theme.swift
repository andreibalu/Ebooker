//
//  Color+Theme.swift
//  Ebooker
//

import SwiftUI
import UIKit

extension Color {
    /// Warm off-white in light mode / warm near-black in dark mode — used as the global app background.
    static let cream = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)   // warm very dark
            : UIColor(red: 0.97, green: 0.955, blue: 0.93, alpha: 1)  // warm off-white
    })

    /// Card surface: warm white in light mode / elevated dark surface in dark mode.
    static let cardWhite = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)   // elevated dark card
            : UIColor(red: 1.0,  green: 0.99, blue: 0.97, alpha: 1)   // warm white
    })
}
