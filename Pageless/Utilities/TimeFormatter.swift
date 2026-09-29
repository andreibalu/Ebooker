//
//  TimeFormatter.swift
//  Pageless
//

import Foundation

enum TimeFormatter {
    /// Upper bound for any duration we accept from remote metadata (~11.5 days).
    /// Far above any real audiobook, far below anything that can overflow `Int`.
    static let maxPlausibleSeconds: Double = 1_000_000

    /// Total conversion: NaN/negative -> 0, huge/infinite -> `maxPlausibleSeconds`.
    static func sanitizedSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return seconds > 0 ? maxPlausibleSeconds : 0 }
        return min(max(seconds, 0), maxPlausibleSeconds)
    }

    /// Whole percent (0...100) for a fraction; never traps on hostile input.
    static func percentValue(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return fraction > 0 ? 100 : 0 }
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    static func clockString(seconds: Double) -> String {
        let totalSeconds = Int(sanitizedSeconds(seconds).rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func durationSummary(seconds: Double) -> String {
        let totalMinutes = Int(sanitizedSeconds(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    static func relativeDateString(for date: Date?) -> String {
        guard let date else { return "Not started" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
