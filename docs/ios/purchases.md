# Purchases

Read this before changing StoreKit products, Unpaged Plus gating, the coffee tip, trial or price copy, or anything App Review sees around purchasing.

## Products and owners

All purchases use StoreKit 2 directly; there is no third-party purchase SDK. Product ids live in `Configuration/` (`PlusProductID`, `AIProductID` with `ICloudSyncProductID`, `CoffeeTipProductID`), and the local test catalog is `Configuration/Products.storekit`. App Store Connect is the production source of prices, offers and localizations.

- **Unpaged Plus** (monthly and yearly subscriptions) unlocks the Apple Intelligence features. `PlusEntitlementStore.shared` owns it and reads `Transaction.currentEntitlements` and `Transaction.updates`.
- **iCloud sync is free**, audio in iCloud included, and has no entitlement check (see `icloud-sync.md`). It used to be part of Plus, so no purchase copy, paywall or Plus hub row may describe it as a Plus feature.
- **Legacy products** stay recognized for existing customers but are no longer sold: the AI Features unlock (non-consumable) and the iCloud Sync monthly subscription. An unrevoked AI unlock counts as permanent Plus, and an active legacy iCloud Sync subscription counts as Plus while it lasts; `PlusEntitlementStoreTests` lock that in. Both groups lost nothing when sync became free: they keep sync and keep Plus. When an active legacy iCloud Sync subscription is what grants Plus, the card says so and that sync itself is now free, so they can decide whether to keep paying. Changing either is a product decision for the owner.
- **Buy me a coffee** is a repeatable consumable owned by `CoffeeTipStore`. It grants nothing and has no restore path, because consumables can't be restored.

There is no synchronous Plus launch cache. It existed only so `AppDelegate` could choose the CloudKit database before StoreKit loaded; with sync free, nothing decided at launch depends on Plus.

## Copy

- Derive trial length and price from the loaded `Product`. `freeTrialDisplay` returns nil unless the introductory offer is `.freeTrial`. Swift code holds no price literals.
- The subscribe button reads "Try …" when a trial exists and "Subscribe" otherwise.
- The local `Products.storekit` carries a free-trial introductory offer on both Plus plans (`paymentMode: "free"`) and a test price for the tip; neither says anything about production.

## App Review reachability (guideline 3.1.1)

The Plus purchase must be reachable in the reviewed build without signing in to iCloud. A build was rejected under 3.1.1 when it wasn't. The path:

- The library header's Plus button (`sparkles`, accessibility id `plusButton`) renders unconditionally and opens `PlusHubView` (`UnpagedPlusCard`).
- Settings → "Unpaged Plus" pushes the same hub as a second path. Settings opens with real settings, and the offer comes after them.
- Nothing in the hub depends on sync or an iCloud account. iCloud has its own Settings section.
- On an iPhone that can't run Apple Intelligence (`AppleIntelligenceCapability.availabilityState == .unsupportedDevice`) the card still offers Plus, but a notice above the plans says the features require an Apple Intelligence–capable iPhone and work on one signed in with the same Apple ID. Hiding the offer there would leave a reviewer on such a device unable to find the purchase; selling it without the notice would sell nothing usable on the device in hand. `-e2e-ai-unsupported-device` plays such an iPhone in fixture launches.

## Coffee tip mechanics

`CoffeeTipStore` loads the one localized consumable and serializes purchases on the main actor. It finishes only verified coffee transactions, including delayed approvals (`Transaction.updates`) and unfinished transactions found at startup (`Transaction.unfinished`). Its state enum distinguishes cancelled, pending, unavailable, failed and succeeded so the UI can say exactly what happened.

## Adding a purchase provider

A third-party provider (RevenueCat was removed) would need a new product and privacy plan, updates to `privacy-policy.md`, `support.md` and `EULA.md`, and verification through TestFlight, since local `Products.storekit` receipts don't reach outside services. Provider credentials stay with the owner, outside the repo.
