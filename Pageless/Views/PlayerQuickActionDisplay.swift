//
//  PlayerQuickActionDisplay.swift
//  Pageless
//

import Foundation

enum PlayerQuickActionDisplay {
    static func playbackRateTitle(for rate: Double) -> String {
        let rounded = (rate * 100).rounded() / 100

        if rounded == rounded.rounded() {
            return "\(Int(rounded))x"
        }

        let oneDecimal = (rounded * 10).rounded() / 10
        if abs(rounded - oneDecimal) < 0.0001 {
            return String(format: "%.1fx", rounded)
        }

        return String(format: "%.2fx", rounded)
    }

    static func sleepTimerTitle(endsAt: Date?, now: Date = Date()) -> String {
        guard let endsAt else {
            return "Sleep Timer"
        }

        let remainingSeconds = max(0, Int(ceil(endsAt.timeIntervalSince(now))))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60

        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
