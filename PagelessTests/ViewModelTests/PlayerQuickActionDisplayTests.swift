//
//  PlayerQuickActionDisplayTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct PlayerQuickActionDisplayTests {

    @Test func playbackRateTitleKeepsFractionalRatesVisible() {
        #expect(PlayerQuickActionDisplay.playbackRateTitle(for: 1.25) == "1.25x")
        #expect(PlayerQuickActionDisplay.playbackRateTitle(for: 1.75) == "1.75x")
    }

    @Test func sleepTimerTitleShowsRemainingCountdown() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(PlayerQuickActionDisplay.sleepTimerTitle(endsAt: nil, now: now) == "Sleep Timer")
        #expect(PlayerQuickActionDisplay.sleepTimerTitle(endsAt: now.addingTimeInterval(65), now: now) == "1:05")
        #expect(PlayerQuickActionDisplay.sleepTimerTitle(endsAt: now.addingTimeInterval(300), now: now) == "5:00")
        #expect(PlayerQuickActionDisplay.sleepTimerTitle(endsAt: now.addingTimeInterval(-3), now: now) == "0:00")
    }

    @Test func settingANewSleepTimerReplacesThePreviousEndDate() {
        let player = AudioPlayerManager()

        player.setSleepTimer(seconds: SleepTimerOption.fiveMinutes.rawValue)
        let firstEndDate = player.sleepTimerEndsAt

        player.setSleepTimer(seconds: SleepTimerOption.thirtyMinutes.rawValue)
        let replacementEndDate = player.sleepTimerEndsAt

        #expect(firstEndDate != nil)
        #expect(replacementEndDate != nil)
        #expect(replacementEndDate! > firstEndDate!)
    }
}
