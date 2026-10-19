//
//  IcloudSyncGate.swift
//  Pageless
//

import Foundation

/// Central decision point for "is iCloud sync currently active for this user?".
/// Factors in the Settings toggle and the iCloud account. Sync is free, so no purchase is involved.
/// Every call site that branches on sync availability must go through this gate
/// rather than reading the toggle directly.
enum IcloudSyncGate {
    static let preferenceKey = "iCloudSyncEnabled"
    nonisolated static let containerIdentifier = "iCloud.andreibaludev.Pageless"

    /// The SwiftData container is selected once per process. This is the immutable runtime
    /// decision used by every sync-sensitive behavior for the rest of this launch.
    static let enabledAtLaunch = evaluate(
        desiredPreference: UserDefaults.standard.bool(forKey: preferenceKey),
        hasUbiquityIdentity: hasUbiquityIdentity()
    )

    static func evaluate(desiredPreference: Bool, hasUbiquityIdentity: Bool) -> Bool {
        desiredPreference && hasUbiquityIdentity
    }

    /// True when (a) the user has turned the toggle on AND (b) the device has a signed-in iCloud
    /// account. When this returns false the SwiftData container is built without
    /// `cloudKitDatabase`. The result is fixed for this process; changing the Settings preference
    /// takes effect after relaunch.
    static func isEnabled() -> Bool {
        enabledAtLaunch
    }

    static func hasUbiquityIdentity() -> Bool {
        #if DEBUG
        // Fixture launches never touch the real account. `-e2e-icloud-account` stands in for a
        // signed-in one so the toggle, relaunch and sync-on UI run without CloudKit.
        if E2EFixtures.enabled { return E2EFixtures.simulatesICloudAccount }
        #endif
        return FileManager.default.ubiquityIdentityToken != nil
    }
}
