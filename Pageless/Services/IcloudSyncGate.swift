//
//  IcloudSyncGate.swift
//  Pageless
//

import Foundation

/// Central decision point for "is iCloud sync currently active for this user?".
/// Factors in the paid subscription, the AppStorage toggle, and the iCloud account.
/// Every call site that branches on sync availability must go through this gate
/// rather than reading the toggle directly.
enum IcloudSyncGate {
    static let preferenceKey = "iCloudSyncEnabled"
    static let containerIdentifier = "iCloud.andreibaludev.Pageless"

    /// The SwiftData container is selected once per process. This is the immutable runtime
    /// decision used by every sync-sensitive behavior for the rest of this launch.
    static let enabledAtLaunch = evaluate(
        subscriptionIsActive: ICloudSubscriptionStore.isSubscribedAtLaunch(),
        desiredPreference: UserDefaults.standard.bool(forKey: preferenceKey),
        hasUbiquityIdentity: hasUbiquityIdentity()
    )

    static func evaluate(
        subscriptionIsActive: Bool,
        desiredPreference: Bool,
        hasUbiquityIdentity: Bool
    ) -> Bool {
        subscriptionIsActive && desiredPreference && hasUbiquityIdentity
    }

    /// True when (a) the iCloud Sync subscription is active, (b) the user has flipped
    /// the toggle on, AND (c) the device has a signed-in iCloud account. When this
    /// returns false the SwiftData container is built without `cloudKitDatabase`. The
    /// result is fixed for this process; changing the Settings preference takes effect
    /// after relaunch.
    static func isEnabled() -> Bool {
        enabledAtLaunch
    }

    static func hasUbiquityIdentity() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
