# Unpaged 1.3.4 release readiness

Audit date: 2026-09-17  
App: Unpaged (`andreibaludev.Pageless`)  
Previous distributed build: 1.3.3 (build 106)

## Versioning

- `VERSION` and all eight target configurations in `Pageless.xcodeproj/project.pbxproj` now use marketing version **1.3.4**.
- `ci_scripts/ci_post_clone.sh` owns the build number in Xcode Cloud. The next build must use a number greater than 106; the checked-in `CURRENT_PROJECT_VERSION = 1` is the local placeholder that CI overwrites.
- `AGENTS.md` now reflects 1.3.4. The App Store Connect 1.3.4 draft exists with release notes and accurate app-review notes saved; no build has been selected or submitted.

## Coffee consumable

The code and local StoreKit fixture use the exact consumable ID `andreibaludev.Pageless.tip.coffee`. The app only thanks the user after a verified transaction, finishes only verified coffee transactions, does not create an entitlement, and does not offer restore. `Products.storekit` parses as valid JSON; both app Info.plists pass `plutil -lint`.

App Store Connect product [6813199756](https://appstoreconnect.apple.com/apps/6761081641/distribution/iaps/6813199756) is created and its saved configuration was verified after reload: English-US “Buy me a coffee” / “Optional one-time support for Unpaged,” all 175 territories including future territories, US$2.99 base pricing (14.99 lei in Romania), inherited tax category, and review notes. Status remains Prepare for Submission. A required screenshot of the in-app purchase screen is still missing and blocks submission. Attach this first consumable to the 1.3.4 submission once the screenshot and eligible uploaded build are available. Before release, run Sandbox/TestFlight checks for localized price, successful verified purchase, cancellation, pending approval, product-load failure/retry, repeat purchase, and a transaction delivered through `Transaction.updates`/`Transaction.unfinished`.

## iOS 27 changes

The typed Foundation Models error mapping, `samplingMode:` migration, and SpeechAnalyzer cancellation teardown are present and availability-gated while the deployment target remains iOS 18. `git diff --check` is clean. This is static evidence only: release readiness still requires the Xcode 27 device build/tests, an iOS 27 Apple Intelligence pass on the physical iPhone 15 Pro, and the iOS 18 fallback/permission matrix. Simulator results cannot qualify the AI surfaces, and no latency or accuracy improvement is established yet.

## External docs and staging hygiene

`support.md`, `privacy-policy.md`, and `EULA.md` contain the coffee-purchase disclosure and are dated 2026-09-17. After accepting the repository change, push their updated content to the public support/privacy/EULA Gists.

Before staging, review untracked generated files deliberately. `.xcodebuildmcp/config.yaml` is local tool configuration; `Pageless.xcodeproj/xcshareddata/xcodecloud/manifest.json` is also currently untracked and should be included only if the release workflow explicitly needs it.
