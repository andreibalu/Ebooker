//
//  PlusProductID.swift
//  Pageless
//

import Foundation

/// Unpaged Plus subscriptions. Keep these IDs in sync with App Store Connect and
/// `Products.storekit`.
nonisolated enum PlusProductID {
    static let monthly = "andreibaludev.Pageless.plus.monthly"
    static let yearly = "andreibaludev.Pageless.plus.yearly"
    static let all = [monthly, yearly]
}
