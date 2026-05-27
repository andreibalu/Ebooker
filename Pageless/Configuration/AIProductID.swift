//
//  AIProductID.swift
//  Pageless
//
//  IAP product ids — must match App Store Connect and Products.storekit.
//  Attach Products.storekit in Xcode: Scheme → Run → Options → StoreKit Configuration.
//

import Foundation

enum AIProductID {
    /// Unlocks on-device AI features (smart moment naming + smart summary).
    static let unlock = "andreibaludev.Pageless.ai_unlock"
}

enum ICloudSyncProductID {
    /// Auto-renewable monthly subscription that unlocks iCloud library sync.
    static let monthly = "andreibaludev.Pageless.icloudsync.monthly"
}
