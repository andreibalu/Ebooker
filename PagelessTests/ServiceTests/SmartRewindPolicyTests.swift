//
//  SmartRewindPolicyTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

/// Isolated because the tier edges (29.9 s vs 30 s, 5 min, the 10 s cap, an unknown elapsed) are
/// cheap to pin here and slow to reach through a two-minute E2E pause.
struct SmartRewindPolicyTests {

    // Catches: a rewind firing on a quick pause to talk, or the boundary moving off 30 s.
    @Test func under30SecondsRewindsNothing() {
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 0, setting: 60) == 0)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 29.9, setting: 60) == 0)
    }

    // Catches: the gentle tier ignoring the 10 s cap, or exceeding a smaller user setting.
    @Test func gentleTierCapsAtTenSecondsAndNeverExceedsTheSetting() {
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 30, setting: 60) == 10)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 299.9, setting: 60) == 10)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 120, setting: 5) == 5)
    }

    // Catches: the full tier starting late (> 5 min) or applying a stale cap.
    @Test func fiveMinutesOrMoreRewindsTheFullSetting() {
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 300, setting: 60) == 60)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 86_400, setting: 30) == 30)
    }

    // Catches: "Off" (0) still rewinding on any tier, including an unknown elapsed.
    @Test func aSettingOfZeroOrLessAlwaysRewindsNothing() {
        for elapsed in [nil, 0, 100, 1_000, Double.nan] as [TimeInterval?] {
            #expect(SmartRewindPolicy.rewindSeconds(elapsed: elapsed, setting: 0) == 0)
            #expect(SmartRewindPolicy.rewindSeconds(elapsed: elapsed, setting: -5) == 0)
        }
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: 1_000, setting: .nan) == 0)
    }

    // Catches: an unmeasurable break (cold start with no history, clock skew) being treated as
    // instant, which would silently drop the user's setting.
    @Test func anUnknownElapsedRewindsTheFullSetting() {
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: nil, setting: 60) == 60)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: -3, setting: 60) == 60)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: .nan, setting: 60) == 60)
        #expect(SmartRewindPolicy.rewindSeconds(elapsed: .infinity, setting: 60) == 60)
    }
}
