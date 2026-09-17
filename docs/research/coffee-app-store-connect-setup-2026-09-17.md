# Unpaged coffee tip: App Store Connect setup

Research and implementation note: 2026-09-17  
App: Unpaged (`andreibaludev.Pageless`)  
Source of truth for the production product: App Store Connect

## Product metadata

Create one In-App Purchase under the Unpaged app:

| Field | Value |
| --- | --- |
| Type | Consumable |
| Product ID | `andreibaludev.Pageless.tip.coffee` |
| Reference name | `Buy me a coffee` |
| Display name (`en-US`) | `Buy me a coffee` |
| Description (`en-US`) | `Optional one-time support for Unpaged.` |
| Production price | Choose the App Store price tier in App Store Connect |

The local `Pageless/Configuration/Products.storekit` file uses **$2.99** as a
tentative equivalent test tier. The app never uses that value as a production
fallback: it displays `Product.displayPrice` from StoreKit, localized for the
customer's storefront. The coordinator should change the local fixture if the
final App Store Connect tier differs.

## Manual App Store Connect checklist

1. Confirm the Paid Apps Agreement, banking, and tax details are active for the
   Account Holder.
2. Open **Apps → Unpaged → Monetization → In-App Purchases → +** and create the
   consumable with the exact product ID above. Do not create a
   subscription or non-consumable for this flow.
3. Add the English display name and description above, choose the production
   price tier, select availability territories, and add any additional
   storefront localizations desired. Complete the applicable tax category.
4. Attach the first consumable to a new app version for App Review. Apple's
   submission guidance requires the first product of each In-App Purchase type
   to be submitted with a new app version; the existing AI non-consumable and
   iCloud subscription do not satisfy the first-consumable requirement.
5. Add the required In-App Purchase review information, including a screenshot
   of the in-app purchase screen, then explain in Review Notes that the Settings
   screen presents an optional,
   one-time tip through StoreKit. It does not unlock features, add content,
   provide priority, or create an entitlement. The same user may purchase it
   again; tips are not restorable.
6. In Sandbox/TestFlight, verify the localized price, successful verified
   purchase, cancellation, pending approval where available, product-loading
   failure, repeat purchase, and an interrupted purchase that arrives through
   `Transaction.updates` or `Transaction.unfinished`.
7. Before release, check the product ID, type, storefront price, localized
   copy, and review notes against the live App Store Connect record. Push the
   updated `support.md`, `privacy-policy.md`, and `EULA.md` content to the
   public policy/support Gists after the repository change is accepted.

## Implementation boundaries

`CoffeeTipStore` is StoreKit 2 only. It finishes only verified transactions,
does not query consumables through `Transaction.currentEntitlements`, does not
offer restore, and does not persist a tip entitlement. The Settings screen
shows a thank-you message only after StoreKit verifies a transaction. Product
loading and purchase failures remain actionable without claiming that a tip was
completed.

## Apple references

- [App Review Guidelines, 3.1.1](https://developer.apple.com/app-store/review/guidelines/)
- [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
- [In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase)
- [Overview of receiving payments](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments/)

These pages and App Store Connect pricing, agreements, review requirements, and
storefront availability can change. Verify them again at submission time.
