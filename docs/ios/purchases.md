# Purchases

Read this before changing StoreKit products, Unpaged Plus gating, the coffee tip, trial or price copy, or anything App Review sees around purchasing.

## Products and owners

All purchases use StoreKit 2 directly; there is no third-party purchase SDK. Product ids live in `Configuration/` (`PlusProductID`, `AIProductID` with `ICloudSyncProductID`, `CoffeeTipProductID`), and the local test catalog is `Configuration/Products.storekit`. App Store Connect is the production source of prices, offers and localizations.

- **Unpaged Plus** (monthly and yearly subscriptions) unlocks AI features and iCloud sync. `PlusEntitlementStore.shared` owns it and reads `Transaction.currentEntitlements` and `Transaction.updates`.
- **Legacy products** stay recognized for existing customers but are no longer sold: the AI Features unlock (non-consumable) and the iCloud Sync monthly subscription. An unrevoked AI unlock counts as permanent Plus, iCloud sync included; `PlusEntitlementStoreTests` lock that in. Changing it is a product decision for the owner.
- **Buy me a coffee** is a repeatable consumable owned by `CoffeeTipStore`. It grants nothing and has no restore path, because consumables can't be restored.

`ICloudSubscriptionStore` survives only for its static launch-cache helpers; nothing uses its shared instance.

## Launch cache

`AppDelegate` must choose the SwiftData CloudKit database before StoreKit's async APIs run, so `PlusEntitlementStore.isSubscribedAtLaunch()` reads a UserDefaults cache that the store writes after each refresh. With no Plus cache yet, it falls back to the old iCloud subscription cache, which honours only a short migration window. The gate built on it is fixed for the process (see `icloud-sync.md`).

## Copy

- Derive trial length and price from the loaded `Product`. `freeTrialDisplay` returns nil unless the introductory offer is `.freeTrial`. Swift code holds no price literals.
- The subscribe button reads "Try …" when a trial exists and "Subscribe" otherwise.
- The local `Products.storekit` carries a free-trial introductory offer on both Plus plans (`paymentMode: "free"`) and a test price for the tip; neither says anything about production.

## App Review reachability (guideline 3.1.1)

The Plus purchase must be reachable in the reviewed build without signing in to iCloud. A build was rejected under 3.1.1 when it wasn't. The path:

- The library header's Plus button (`sparkles`, accessibility id `plusButton`) renders unconditionally and opens `PlusHubView` (`UnpagedPlusCard`).
- Settings → "Unpaged Plus" pushes the same hub as a second path. Settings opens with real settings, and the offer comes after them.
- Only the hub's iCloud Library row depends on sync being on.

## Coffee tip mechanics

`CoffeeTipStore` loads the one localized consumable and serializes purchases on the main actor. It finishes only verified coffee transactions, including delayed approvals (`Transaction.updates`) and unfinished transactions found at startup (`Transaction.unfinished`). Its state enum distinguishes cancelled, pending, unavailable, failed and succeeded so the UI can say exactly what happened.

## Adding a purchase provider

A third-party provider (RevenueCat was removed) would need a new product and privacy plan, updates to `privacy-policy.md`, `support.md` and `EULA.md`, and verification through TestFlight, since local `Products.storekit` receipts don't reach outside services. Provider credentials stay with the owner, outside the repo.
