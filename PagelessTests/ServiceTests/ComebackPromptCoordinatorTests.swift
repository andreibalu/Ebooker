//
//  ComebackPromptCoordinatorTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct ComebackPromptCoordinatorTests {
    private func happyInputs(lastPlayedHoursAgo: Double) -> ComebackPromptInputs {
        ComebackPromptInputs(
            lastPlayedAt: Date(timeIntervalSinceNow: -lastPlayedHoursAgo * 3600),
            hasProgressPosition: true,
            useLocalAIFeatures: true,
            useComebackRecap: true,
            canUseAIFeatures: true,
            capabilityAvailable: true
        )
    }

    @Test func offersWhenLastPlayed5HoursAgo() {
        let inputs = happyInputs(lastPlayedHoursAgo: 5)
        #expect(ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenLastPlayedJustOneHourAgo() {
        let inputs = happyInputs(lastPlayedHoursAgo: 1)
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsAtExactly4HoursMinus1Second() {
        var inputs = happyInputs(lastPlayedHoursAgo: 0)
        inputs.lastPlayedAt = Date(timeIntervalSinceNow: -(4 * 3600 - 1))
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func offersExactlyAt4Hours() {
        var inputs = happyInputs(lastPlayedHoursAgo: 0)
        inputs.lastPlayedAt = Date(timeIntervalSinceNow: -4 * 3600)
        #expect(ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenLastPlayedAtIsNil() {
        var inputs = happyInputs(lastPlayedHoursAgo: 10)
        inputs.lastPlayedAt = nil
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenNoProgressPosition() {
        var inputs = happyInputs(lastPlayedHoursAgo: 5)
        inputs.hasProgressPosition = false
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenComebackToggleOff() {
        var inputs = happyInputs(lastPlayedHoursAgo: 5)
        inputs.useComebackRecap = false
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenMasterAIToggleOff() {
        var inputs = happyInputs(lastPlayedHoursAgo: 5)
        inputs.useLocalAIFeatures = false
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenEntitlementExhausted() {
        var inputs = happyInputs(lastPlayedHoursAgo: 5)
        inputs.canUseAIFeatures = false
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func skipsWhenCapabilityUnavailable() {
        var inputs = happyInputs(lastPlayedHoursAgo: 5)
        inputs.capabilityAvailable = false
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
    }

    @Test func customThresholdRespected() {
        let inputs = happyInputs(lastPlayedHoursAgo: 2)
        #expect(!ComebackPromptCoordinator.shouldOffer(inputs))
        #expect(ComebackPromptCoordinator.shouldOffer(inputs, threshold: 1 * 3600))
    }
}
