//
//  MockAIEntitlementStore.swift
//  PagelessTests
//

import Foundation
@testable import Pageless

final class MockAIEntitlementStore: AIEntitlementChecking {
    var isUnlocked: Bool
    var trialUsesRemaining: Int
    private(set) var consumeTrialUseCallCount = 0

    init(isUnlocked: Bool = false, trialUsesRemaining: Int = AIEntitlementStore.initialTrialUses) {
        self.isUnlocked = isUnlocked
        self.trialUsesRemaining = trialUsesRemaining
    }

    var canUseAIFeatures: Bool {
        isUnlocked || trialUsesRemaining > 0
    }

    func consumeTrialUse() {
        guard !isUnlocked, trialUsesRemaining > 0 else { return }
        trialUsesRemaining -= 1
        consumeTrialUseCallCount += 1
    }
}
