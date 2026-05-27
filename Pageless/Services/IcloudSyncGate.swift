//
//  IcloudSyncGate.swift
//  Pageless
//

import Foundation

/// Central decision point for "is iCloud sync currently active for this user?".
/// Today this is the AppStorage toggle in `SettingsView`; later this will also factor in a
/// paid subscription check, so every call site that branches on sync availability must go
/// through this gate rather than reading the toggle directly.
enum IcloudSyncGate {
    static let preferenceKey = "iCloudSyncEnabled"
    static let containerIdentifier = "iCloud.andreibaludev.Pageless"

    /// True when (a) the iCloud Sync subscription is active, (b) the user has flipped
    /// the toggle on, AND (c) the device has a signed-in iCloud account. When this
    /// returns false the SwiftData container is built without `cloudKitDatabase`.
    static func isEnabled() -> Bool {
        guard ICloudSubscriptionStore.isSubscribedAtLaunch() else { return false }
        guard UserDefaults.standard.bool(forKey: preferenceKey) else { return false }
        return hasUbiquityIdentity()
    }

    static func hasUbiquityIdentity() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
