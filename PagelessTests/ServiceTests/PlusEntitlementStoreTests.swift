//
//  PlusEntitlementStoreTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct PlusEntitlementStoreTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func noRecognizedEntitlementReturnsFalse() {
        let records = [
            PlusEntitlementRecord(
                productID: "andreibaludev.Pageless.tip.coffee",
                expirationDate: nil,
                revocationDate: nil
            ),
            PlusEntitlementRecord(
                productID: "unknown.product",
                expirationDate: now.addingTimeInterval(86_400),
                revocationDate: nil
            )
        ]

        #expect(!PlusEntitlementStore.hasPlusEntitlement(in: records, now: now))
    }

    @Test func expiredLegacyICloudDoesNotEntitleButOwnedAIUnlockStillDoes() {
        let expiredICloudSubscription = PlusEntitlementRecord(
            productID: ICloudSyncProductID.monthly,
            expirationDate: now.addingTimeInterval(-1),
            revocationDate: nil
        )
        let ownedAIUnlock = PlusEntitlementRecord(
            productID: AIProductID.unlock,
            expirationDate: nil,
            revocationDate: nil
        )

        #expect(!PlusEntitlementStore.hasPlusEntitlement(
            in: [expiredICloudSubscription],
            now: now
        ))
        #expect(PlusEntitlementStore.hasPlusEntitlement(
            in: [expiredICloudSubscription, ownedAIUnlock],
            now: now
        ))
    }

    @Test func revokedLegacyAIPurchaseDoesNotEntitle() {
        let revokedAIUnlock = PlusEntitlementRecord(
            productID: AIProductID.unlock,
            expirationDate: nil,
            revocationDate: now.addingTimeInterval(-100)
        )

        #expect(!PlusEntitlementStore.hasPlusEntitlement(in: [revokedAIUnlock], now: now))
    }
}
