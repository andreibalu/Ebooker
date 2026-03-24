//
//  AIProductID.swift
//  Pageless
//
//  Non-consumable IAP product id — must match App Store Connect and Products.storekit.
//  Attach Products.storekit in Xcode: Scheme → Run → Options → StoreKit Configuration.
//

import Foundation

enum AIProductID {
    /// Unlocks on-device AI features (smart moment naming + smart summary).
    static let unlock = "andreibaludev.Pageless.ai_unlock"
}
