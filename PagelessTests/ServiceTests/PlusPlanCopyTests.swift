import Foundation
import StoreKit
import Testing
@testable import Pageless

/// Plan labels come from StoreKit's `subscriptionPeriod`, which describes a *quantity*
/// ("1 month"). These read as plan names and prose instead, so the card never shows
/// "1 Month" on a chip or "$2.99 per 1 month" in its terms.
struct PlusPlanCopyTests {
    @Test func planChipsReadAsPlanNames() {
        #expect(PlusEntitlementStore.planNameDisplay(value: 1, unit: .month) == "Monthly")
        #expect(PlusEntitlementStore.planNameDisplay(value: 1, unit: .year) == "Yearly")
        #expect(PlusEntitlementStore.planNameDisplay(value: 1, unit: .week) == "Weekly")
    }

    @Test func multiUnitPlansKeepTheirQuantity() {
        #expect(PlusEntitlementStore.planNameDisplay(value: 3, unit: .month) == "3 Months")
        #expect(PlusEntitlementStore.perPeriodDisplay(value: 3, unit: .month) == "3 months")
    }

    @Test func pricingTermsDropTheLeadingOne() {
        #expect(PlusEntitlementStore.perPeriodDisplay(value: 1, unit: .month) == "month")
        #expect(PlusEntitlementStore.perPeriodDisplay(value: 1, unit: .year) == "year")
    }

    /// Guards the local StoreKit config against drift: the card's "Try 1 week free"
    /// button only appears when the product actually carries a free-trial intro offer.
    /// `P1W` is how a seven-day trial is expressed — App Store Connect offers the
    /// duration as "1 week".
    @Test func bothPlusPlansCarryAOneWeekTrialInTheLocalConfig() throws {
        let url = try #require(Bundle.main.url(forResource: "Products", withExtension: "storekit"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))

        var offerByProductID: [String: [String: Any]] = [:]
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let id = dict["productID"] as? String,
                   let offer = dict["introductoryOffer"] as? [String: Any] {
                    offerByProductID[id] = offer
                }
                dict.values.forEach(walk)
            } else if let array = node as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)

        for productID in PlusProductID.all {
            let offer = try #require(offerByProductID[productID], "\(productID) has no intro offer")
            #expect(offer["paymentMode"] as? String == "free")
            #expect(offer["subscriptionPeriod"] as? String == "P1W")
        }
    }
}
