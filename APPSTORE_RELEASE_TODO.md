# Unpaged — App Store Release Checklist

Last audit: 2026-05-17. Scope: everything **mandatory** to ship 1.0 to the App Store, excluding marketing assets (icon polish, screenshots, listing copy) which you've said you'll handle separately.

Legend:
- 🚨 **HARD BLOCKER** — submission will fail or app will be rejected
- 🟡 **REQUIRED** — must be done before tapping "Submit for Review"
- 🟠 **STRONGLY RECOMMENDED** — high rejection risk if skipped
- 🟢 **NICE TO HAVE** — non-blocking polish

---

## 🚨 Hard Blockers

### 1. ~~CarPlay entitlement approval~~ ✅ DONE
- CarPlay entitlement already granted by Apple and confirmed working on a real head unit by Andrei.
- No code change needed.

### 2. Privacy Manifest (`PrivacyInfo.xcprivacy`) — missing
- Apple requires this file for all apps as of 2024-05. None exists in the repo.
- **Action**: add `Pageless/PrivacyInfo.xcprivacy` declaring:
  - `NSPrivacyTracking` = `false` (app does no cross-app tracking)
  - `NSPrivacyTrackingDomains` = `[]`
  - `NSPrivacyCollectedDataTypes` = `[]` (you don't collect/upload any user data)
  - `NSPrivacyAccessedAPITypes` for the required-reason APIs you actually use:
    - `NSPrivacyAccessedAPICategoryFileTimestamp` (you read file dates in import/library code) — reason `C617.1` (display to user) or `0A2A.1` (inside app)
    - `NSPrivacyAccessedAPICategoryUserDefaults` (heavy use via `@AppStorage`, onboarding, IAP store) — reason `CA92.1` (access info from same app)
    - `NSPrivacyAccessedAPICategoryDiskSpace` — only if you actually read free disk space anywhere (search the code; if not, omit)
    - `NSPrivacyAccessedAPICategorySystemBootTime` — only if used; omit otherwise
- Reference: [Apple required-reason API list](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api).
- Add the file to the `Pageless` target in `Pageless.xcodeproj` (it must be in the bundle).

### 3. In-App Purchase
**Code-side audit: PASSING.** Read of `Pageless/Services/AIEntitlementStore.swift`, `Pageless/Configuration/AIProductID.swift`, `Pageless/Configuration/Products.storekit`, `Pageless/Views/AISettingsView.swift`, and `Pageless.xcodeproj/xcshareddata/xcschemes/Pageless.xcscheme`:

- ✅ Product ID `andreibaludev.Pageless.ai_unlock` matches across `Products.storekit`, `AIProductID.swift`, and is the single source consumed by `AIEntitlementStore` and `AISettingsView`
- ✅ `Products.storekit` is wired to the Run action of the `Pageless` scheme — simulator builds get the local config automatically
- ✅ `StoreKit.framework` is linked in `project.pbxproj`
- ✅ StoreKit 2 implementation follows Apple's reference pattern:
  - `Transaction.updates` listener started in `init` ([AIEntitlementStore.swift:37](Pageless/Services/AIEntitlementStore.swift:37)) — catches background renewals, Ask-to-Buy approvals, restored purchases
  - `Transaction.currentEntitlements` queried on startup ([AIEntitlementStore.swift:79](Pageless/Services/AIEntitlementStore.swift:79))
  - `verified` vs `unverified` split correctly ([AIEntitlementStore.swift:104](Pageless/Services/AIEntitlementStore.swift:104))
  - `transaction.finish()` called on both purchase **and** background updates ([AIEntitlementStore.swift:108](Pageless/Services/AIEntitlementStore.swift:108), [140](Pageless/Services/AIEntitlementStore.swift:140))
  - `AppStore.sync()` used for restore ([AIEntitlementStore.swift:128](Pageless/Services/AIEntitlementStore.swift:128)) — this is the correct StoreKit 2 API, not the deprecated `restoreCompletedTransactions`
  - `AppStore.canMakePayments` checked + buy button disabled when false
  - `userCancelled` and `pending` cases handled
  - Product-ID guard on every transaction prevents cross-product mix-ups
- ✅ Restore button visible across all three UI states (unlocked / can-purchase / can't-purchase-on-this-device) at lines 267/298/310 of `AISettingsView.swift`
- ✅ Trial counter (5 free uses) persists in UserDefaults, is correctly gated by `isUnlocked`, and the master toggle locks out further usage once exhausted

**Minor code issues worth fixing (not blockers, but low effort):**
- ⚠️ `unlockPriceDisplay` falls back to a hardcoded `"3.99"` ([AIEntitlementStore.swift:52](Pageless/Services/AIEntitlementStore.swift:52)) used by `AISettingsView.swift:291`. If StoreKit fetch is slow/fails, users briefly see the wrong currency or stale price. Apple sometimes flags hardcoded prices. Recommend showing a dash or a small spinner until `product` resolves.
- ⚠️ `.pending` purchase result is surfaced as `purchaseError = "Purchase is pending approval."` ([AIEntitlementStore.swift:116](Pageless/Services/AIEntitlementStore.swift:116)). Pending is a normal Family Sharing "Ask to Buy" / SCA flow, not an error. Show it as info copy, not an alert titled "Purchase".
- ⚠️ Redundant `objectWillChange.send()` in `consumeTrialUse()` ([AIEntitlementStore.swift:61](Pageless/Services/AIEntitlementStore.swift:61)) — the `@Published trialUsesRemaining` already triggers it.

**App Store Connect side — STILL REQUIRED:**
The local `.storekit` file lets you simulate purchases in the simulator, but the real App Store fetches from App Store Connect. Before your first TestFlight upload:
  1. In App Store Connect → your app → Monetization → In-App Purchases → create **Non-Consumable** with product ID `andreibaludev.Pageless.ai_unlock` (exact match required)
  2. Set price tier to match $3.99 (or your chosen launch price)
  3. Fill display name + description in every locale you ship
  4. Upload a 1024×1024 review screenshot showing the IAP UI (the `AISettingsView` purchase pane)
  5. Submit IAP **alongside** your first binary build (App Review rejects IAP-using apps if the IAP itself isn't submitted in the same review)
  6. After submission, the IAP enters "Waiting for Review" — that's expected. It ships with the app.

**How to verify the IAP works end-to-end** (two options, pick one):
- **Simulator + local .storekit (fastest, fully offline)**: Open the project in Xcode → run on any iOS 26.2 simulator → Settings → AI Features → tap "Unlock — $3.99". Because `Products.storekit` is attached to the scheme, the purchase succeeds against the local config with no Apple ID prompt. Then tap "Restore purchases" to confirm restore works. Delete app + reinstall to confirm `Transaction.currentEntitlements` repopulates.
- **Device + sandbox tester (closer to real)**: Requires steps 1–4 above to be done first, plus a sandbox tester created in App Store Connect → Users and Access → Sandbox Testers, signed in on your iPhone 15 at Settings → App Store → Sandbox Account. Then a normal TestFlight build will hit sandbox.

If you'd like, I can run the simulator + local .storekit flow now and screenshot the result — that's the one case where I'd build to simulator instead of your iPhone 15, because device IAP testing requires the App Store Connect setup that's still TODO.

### 4. App icon — likely placeholders
- `Pageless/Assets.xcassets/AppIcon.appiconset/` contains `iconResized.png`, `iconResized 1.png`, `iconResized 2.png` (light / dark / tinted). Filenames suggest these are workmark/test exports.
- **Action**: replace with final 1024×1024 PNG (sRGB, no alpha) variants. App Store Connect will reject icons with alpha, transparency, or rounded corners. Rename to non-spaced filenames (`AppIcon-1024.png`, `AppIcon-1024-Dark.png`, `AppIcon-1024-Tinted.png`) and update `Contents.json`.

### 5. Marketing version mismatch
- `Pageless.xcodeproj/project.pbxproj` has `MARKETING_VERSION = 1.0`
- Repo root `VERSION` file says `1.1`
- App Store Connect uses `MARKETING_VERSION`.
- **Action**: pick one and align both. For a first release, `1.0` in pbxproj + `VERSION` is conventional.

### 6. Privacy Policy URL — none in the project
- Apps that use the mic, speech recognition, or sell IAP **must** provide a privacy policy URL in the App Store Connect listing.
- The IAP requirement also means a privacy policy link should be **inside the app** (typically in Settings).
- **Action**:
  1. Write a privacy policy (template: data stays on-device, mic used only for CarPlay voice search and not stored, speech recognition uses Apple's on-device model, no analytics, no third-party SDKs, IAP processed by Apple).
  2. Host it on a stable URL (Notion public page, GitHub Pages, your own domain).
  3. Add the URL to App Store Connect → App Privacy → Privacy Policy URL.
  4. Add a "Privacy Policy" row in `Pageless/Views/SettingsView.swift` and `Pageless/Views/AISettingsView.swift` that opens the URL via `Link(...)`.

### 7. Terms / EULA link for IAP — none in the project
- Apple's standard EULA is used by default unless you provide your own. If you accept that, you just need the privacy policy link.
- However, the IAP screen in `Pageless/Views/AISettingsView.swift` shows price + restore button — Apple expects a "Terms of Use" link visible **on the purchase screen** (in addition to the restore button you already have at lines 267/298/310).
- **Action**: add an inline "Terms of Use" link pointing to Apple's standard EULA URL (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) on the purchase pane. Alternatively write your own EULA — Apple's standard is fine.

---

## 🟡 Required Before Submit

### 8. Deployment target sanity check
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` (iOS 26.2). This is extremely narrow — only the latest iOS users can install. You're already gating Apple Intelligence at runtime via `AppleIntelligenceCapability`.
- **Action**: decide intentionally.
  - **Keep 26.2** if you rely on iOS 26-only frameworks beyond FoundationModels (which is the only obvious 26-only thing here).
  - **Lower to 18.0** or **17.0** for a wider audience — FoundationModels is already runtime-gated and the AI features are explicitly opt-in. Most of the app (audio playback, library, EQ, LibriVox) works fine without it.
- This choice also affects which simulators/devices you can test on.

### 9. iPad support — decide intentionally
- `TARGETED_DEVICE_FAMILY = "1,2"` means the app is offered to **both iPhone and iPad** on the App Store. App Review **will test on iPad** and reject for broken layouts.
- **Action**: either test every screen on an iPad (especially `ContentView`, `PlayerView`, `AudiobookDetailView`, `BrowseLibriVoxView`, `EqualizerSheet`, `MomentEditSheet`) and fix any obviously-broken layouts — or change `TARGETED_DEVICE_FAMILY` to `"1"` to ship iPhone-only for 1.0 and revisit iPad later.

### 10. Build number bumping
- `CURRENT_PROJECT_VERSION = 1`. Fine for the first TestFlight build, but every subsequent upload to App Store Connect **must** have a strictly higher build number for the same marketing version.
- **Action**: set a versioning workflow now (e.g., increment to `2` for the second upload). Consider a `ci_scripts/` step to bump automatically.

### 11. App Store Connect "App Privacy" questionnaire
- Required before submission. You have to declare every data type collected.
- **Action**: in App Store Connect → App Privacy, declare:
  - **Data Not Collected** for everything that stays on-device (library, moments, playback progress, EQ settings, IAP state). This is most of the app.
  - Microphone audio: not collected (CarPlay voice search → fed to Apple's on-device Speech recognizer → discarded).
  - Speech recognition: not collected.
  - Confirm the answers match your privacy policy and `PrivacyInfo.xcprivacy`.

### 12. Encryption export compliance — already declared
- `Info.plist` has `ITSAppUsesNonExemptEncryption = false`. ✅ This is fine because you only use HTTPS (exempt). No further action needed unless you add custom crypto.

### 13. LibriVox attribution
- LibriVox audio is public domain (CC0) so attribution is **not legally required**, but their [content policy](https://librivox.org/pages/about-us/) requests credit. App Review has historically flagged apps repackaging LibriVox without acknowledgement.
- **Action**: add a one-line credit in `Pageless/Views/SettingsView.swift` (e.g., "Free books courtesy of LibriVox.org — public domain audio") and on `Pageless/Views/FreeBooks/BrowseLibriVoxView.swift` as a footer.

### 14. Network reachability for LibriVox + streaming books
- LibriVox API + streaming-only `Audiobook` items require network. App Review tests on poor/no network.
- **Action**: verify that `BrowseLibriVoxView`, `LibriVoxBookDetailView`, `SamplePlayer`, and streaming `Audiobook` playback all show a clean offline message via `NetworkMonitor.shared.isConnected` rather than spinning forever or crashing. Test by toggling airplane mode on the device build.

### 15. CarPlay reviewer instructions
- App Review tests CarPlay using a simulator. They expect either:
  - A working CarPlay simulator flow they can exercise, **or**
  - Reviewer notes explaining how to trigger CarPlay (Xcode → Window → Simulator → I/O → External Displays → CarPlay).
- **Action**: in App Store Connect → App Review Information → Notes, document the CarPlay flow + that voice search needs the mic permission prompt to be triggered on iPhone first.

---

## 🟠 Strongly Recommended

### 16. Smoke-test the legacy seed catalog path
- `FreeBookCatalogService` / `FreeBookDownloadService` / `Pageless/Resources/FreeBookCatalog.json` (5 books from archive.org) are still used by CarPlay. Confirm they still resolve — archive.org URLs in `FreeBookCatalog.json` should all 200.
- If any are broken, App Review will flag CarPlay as crashing.

### 17. Remove or downgrade fatalError on ModelContainer failure
- `Pageless/App/AppDelegate.swift:43` crashes the app if SwiftData container creation fails. This is normally fine — but if a future migration ever fails for a real user, the app crash-loops with no recovery.
- **Action (optional)**: catch the error and present a "Storage couldn't be opened, contact support" screen. Not a blocker for 1.0.

### 18. Onboarding rerun for review
- Apple reviewers see a fresh install. Make sure the onboarding flow (`OnboardingManager` 4 phases, 7 spotlight steps) actually completes without dead-ends. Run a clean simulator install and walk through it.

### 19. App Store description must mention key permissions in plain language
- Your `Info.plist` usage strings (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) are good. Make sure the App Store description also explains why those prompts appear — reviewers prefer this and so do users.

### 20. Apple Intelligence gating UX
- For users on devices that can't run FoundationModels (anything below iPhone 15 Pro / M-series iPad), `AppleIntelligenceCapability` should hide AI buttons. Verify on a non-AI device that:
  - AI moment naming UI is absent
  - Recap UI is absent
  - AI Settings page makes clear the device doesn't support AI (rather than "buy to unlock")
- App Review **will** test on a non-AI device.

### 21. App rating
- App Store Connect requires an age rating questionnaire. Free books include classics with violence (Frankenstein), so rating will likely come out 9+ or 12+. Answer truthfully.

### 22. Subscription / IAP messaging audit
- Re-read every line in `AISettingsView.swift` showing the IAP price/state. Apple rejects vague IAP copy. Confirm:
  - Exact price + currency are dynamically loaded from StoreKit (not hardcoded as "$3.99")
  - "Restore purchases" is visible on all states (already present, lines 267 / 298 / 310 ✅)
  - The free trial behaviour (`AIEntitlementStore` trial counter) is explained to the user before they're asked to pay

---

## 🟢 Nice to Have

### 23. Replace test icon filenames
- The space in `iconResized 1.png` / `iconResized 2.png` is technically allowed but flaky in some build steps. Rename when you swap to final art.

### 24. Strip the temp `iconResized*` images from the repo once final art lands
- Otherwise they sit in git history confusing future-you.

### 25. Privacy-friendly first-launch hint about mic permission
- The app primes mic + speech permission on first launch via `VoiceSearchPermissions.primeIfNeeded()`. Users see a system prompt with no context. Consider showing a one-line in-app explanation **before** triggering the prompt — improves grant rate and is what Apple Reviewer Guidelines 5.1.1(ii) recommends.

### 26. TestFlight beta
- Run at least one TestFlight build (internal or external) for a few days. Catches signing/IAP issues that simulator builds hide.

### 27. CI build script audit
- `ci_scripts/` exists — verify it doesn't bake in dev-only flags into release builds. Xcode Cloud will execute these on every archive.

### 28. Crash reporting / analytics
- The app currently has no third-party crash reporting. This is **good** from a privacy standpoint, but you'll be flying blind on production crashes. Consider enabling Xcode Organizer crash reports (free, no SDK, no privacy implications) — make sure you've opted in under Xcode → Preferences → Accounts → your team.

---

## 📋 App Store Connect Checklist (no code changes)

The following are pure App Store Connect data entry — list them so nothing is forgotten:

- [ ] App name reserved: **Unpaged**
- [ ] Bundle ID registered: `andreibaludev.Pageless` (matches `CFBundleIdentifier`)
- [ ] SKU set
- [ ] Primary category: **Books** (secondary: maybe Entertainment)
- [ ] Age rating questionnaire
- [ ] App Privacy questionnaire (item #11)
- [ ] Privacy Policy URL (item #6)
- [ ] Support URL (mandatory — a contact page or email-only landing page works)
- [ ] Marketing URL (optional)
- [ ] Promotional text (170 chars, can be updated without resubmission)
- [ ] Description + keywords + subtitle
- [ ] Screenshots: iPhone 6.7" + 6.1" (required); iPad 12.9" if you keep iPad support
- [ ] App preview videos (optional)
- [ ] CarPlay screenshot (required if CarPlay entitlement is shipped)
- [ ] IAP product `andreibaludev.Pageless.ai_unlock` created + screenshot + review notes (item #3)
- [ ] App Review notes covering: CarPlay how-to (item #15), AI features require Apple Intelligence-capable device, IAP testing instructions, demo content (LibriVox books) is publicly available
- [ ] Sign-in not required ✅ (App Review otherwise demands a demo account)
- [ ] Export compliance: select "Uses only exempt encryption" (matches `ITSAppUsesNonExemptEncryption = false`)
- [ ] Build uploaded via Xcode Organizer or Xcode Cloud, processed, attached to version

---

## Suggested Order of Operations

1. **Today**: submit the CarPlay entitlement request form (long lead time). Decide on iOS deployment target + iPad support.
2. **This week**: write privacy policy, host it, add `PrivacyInfo.xcprivacy`, add Privacy Policy + Terms links in `SettingsView` / `AISettingsView`, add LibriVox attribution.
3. **Before first TestFlight upload**: create the IAP in App Store Connect with matching ID, replace app icons, align marketing version, smoke-test seed catalog URLs, run through onboarding on a fresh install.
4. **TestFlight phase**: walk every screen on iPhone + iPad (if kept), test offline, test on a non-AI-capable device, test IAP purchase + restore.
5. **Final submission**: fill App Privacy questionnaire, App Review notes (CarPlay instructions, demo flow), submit binary + IAP together.
