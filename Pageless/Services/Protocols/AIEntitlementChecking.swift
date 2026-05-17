//
//  AIEntitlementChecking.swift
//  Pageless
//

import Foundation

/// Minimal read-only surface needed by views and view models to gate AI features.
/// Conforming to this protocol (rather than referencing `AIEntitlementStore` directly
/// in logic) enables lightweight test doubles without importing StoreKit.
protocol AIEntitlementChecking: AnyObject {
    /// True after the non-consumable is purchased and the transaction is verified.
    var isUnlocked: Bool { get }
    /// Number of free trial uses still available.
    var trialUsesRemaining: Int { get }
    /// True when either `isUnlocked` or `trialUsesRemaining > 0`.
    var canUseAIFeatures: Bool { get }
    /// Decrement the trial counter after a successful on-device AI run.
    func consumeTrialUse()
}

extension AIEntitlementStore: AIEntitlementChecking {}
