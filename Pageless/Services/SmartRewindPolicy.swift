//
//  SmartRewindPolicy.swift
//  Pageless
//

import Foundation

/// How far Smart Rewind steps back when playback resumes after a break. The Settings "On Resume"
/// option is the maximum; shorter breaks rewind less. See `docs/ios/playback.md`.
enum SmartRewindPolicy {
    /// A break shorter than this resumes in place (pausing to talk to someone).
    static let instantResumeBelow: TimeInterval = 30
    /// A break shorter than this is gentle: the setting capped at `gentleRewindCap`.
    static let gentleBreakBelow: TimeInterval = 5 * 60
    static let gentleRewindCap: Double = 10

    /// - Parameters:
    ///   - elapsed: seconds since playback stopped. nil, negative or non-finite means the break
    ///     can't be measured, which rewinds the full setting.
    ///   - setting: the On Resume seconds. Zero or less (or non-finite) disables rewinding.
    static func rewindSeconds(elapsed: TimeInterval?, setting: Double) -> Double {
        guard setting.isFinite, setting > 0 else { return 0 }
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return setting }
        if elapsed < instantResumeBelow { return 0 }
        if elapsed < gentleBreakBelow { return min(setting, gentleRewindCap) }
        return setting
    }
}
