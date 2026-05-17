//
//  AIEntitlementCheckingTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

@MainActor
struct AIEntitlementCheckingTests {

    // MARK: - canUseAIFeatures

    @Test func canUseAIFeaturesWhenUnlocked() {
        let store = MockAIEntitlementStore(isUnlocked: true, trialUsesRemaining: 0)
        #expect(store.canUseAIFeatures == true)
    }

    @Test func canUseAIFeaturesWhenTrialRemainingAndNotUnlocked() {
        let store = MockAIEntitlementStore(isUnlocked: false, trialUsesRemaining: 3)
        #expect(store.canUseAIFeatures == true)
    }

    @Test func cannotUseAIFeaturesWhenNotUnlockedAndTrialExhausted() {
        let store = MockAIEntitlementStore(isUnlocked: false, trialUsesRemaining: 0)
        #expect(store.canUseAIFeatures == false)
    }

    // MARK: - consumeTrialUse

    @Test func consumeTrialUseDecrementsRemaining() {
        let store = MockAIEntitlementStore(isUnlocked: false, trialUsesRemaining: 3)
        store.consumeTrialUse()
        #expect(store.trialUsesRemaining == 2)
        #expect(store.consumeTrialUseCallCount == 1)
    }

    @Test func consumeTrialUseIsNoOpWhenUnlocked() {
        let store = MockAIEntitlementStore(isUnlocked: true, trialUsesRemaining: 5)
        store.consumeTrialUse()
        #expect(store.trialUsesRemaining == 5)
        #expect(store.consumeTrialUseCallCount == 0)
    }

    @Test func consumeTrialUseIsNoOpWhenTrialExhausted() {
        let store = MockAIEntitlementStore(isUnlocked: false, trialUsesRemaining: 0)
        store.consumeTrialUse()
        #expect(store.trialUsesRemaining == 0)
        #expect(store.consumeTrialUseCallCount == 0)
    }

    @Test func multipleConsumesReachZero() {
        let store = MockAIEntitlementStore(isUnlocked: false, trialUsesRemaining: 2)
        store.consumeTrialUse()
        store.consumeTrialUse()
        #expect(store.trialUsesRemaining == 0)
        #expect(store.canUseAIFeatures == false)
        store.consumeTrialUse()
        #expect(store.trialUsesRemaining == 0)
    }

    // MARK: - Protocol conformance on real store

    @Test func realAIEntitlementStoreInitialState() {
        let store = AIEntitlementStore()
        #expect(store.isUnlocked == false)
        #expect(store.trialUsesRemaining == AIEntitlementStore.initialTrialUses)
        #expect(store.canUseAIFeatures == true)
    }

    @Test func realAIEntitlementStoreConformsToProtocol() {
        let store: any AIEntitlementChecking = AIEntitlementStore()
        #expect(store.canUseAIFeatures == true)
    }
}
