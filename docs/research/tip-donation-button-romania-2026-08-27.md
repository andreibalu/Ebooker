# Tip/donation button for an iOS developer in Romania

Research date: 2026-08-27
Scope: Romania-based individual or small developer, iOS app distributed through the Apple App Store, with a voluntary “tip me a coffee” request.
Repository convention: no existing research-note directory or format was found; this note establishes `docs/research/` for this finding.

## Executive recommendation

Use a small support page on the developer’s own website, with either a personal Revolut.Me link for a genuinely personal gift or a Revolut Pro payment link for declared professional support. If the button is placed inside the App Store app, describe it as an entirely optional gift to the individual developer, give no feature/content/access in return, and ensure 100% of the money reaches that individual. Apple’s Guideline 3.2.1(vii) expressly permits that narrow pattern.

If the payment is really compensation for the app, its content, or an ongoing service—or if the recipient is a company—use an Apple consumable In-App Purchase with fixed tip tiers. Apple’s Guideline 3.1.1 expressly permits IAP currencies to be used to tip the developer. This is the clearest App Review path, but Apple handles the checkout and pays proceeds later.

Stripe is technically available in Romania and has a good hosted “customers choose what to pay” Payment Link, but Stripe’s own policy says a tip must be for goods or services already provided and that Stripe does not support personal or peer-to-peer money transmission. Therefore, Stripe is a better fit for a professional service tip than for a pure personal gift.

## Decision matrix

| Option | User payment experience | Developer receives/withdraws | App Store position | Recommendation |
|---|---|---|---|---|
| Apple consumable IAP tip tiers | Native App Store sheet; user pays with their Apple payment method | Apple pays the proceeds to the primary bank account in App Store Connect, normally within 45 days after the relevant fiscal month, subject to agreement, bank/tax setup, and threshold | Explicitly permitted for tipping the developer under 3.1.1; use StoreKit and App Store Connect | Best when the tip is connected to the app, its content, or service, or when the recipient is a company |
| Personal Revolut.Me / Revolut payment-request link | User opens the link, enters an amount, and pays from Revolut or by card; limits and eligibility are shown in the Revolut app | Funds arrive in the Revolut account; move them to a personal Revolut account or external bank account | Potentially fits Apple 3.2.1(vii) only when it is an optional personal gift, 100% reaches the individual recipient, and no digital benefit is attached | Best low-friction route for a true gift to an individual; keep copy explicit and non-transactional |
| Revolut Pro Payment Link | Hosted checkout; user can pay through supported cards, Revolut Pay, and digital-wallet methods shown at checkout | Settlement goes to the Pro account; transfer from Pro to an external bank or personal Revolut account | Treat as a professional payment, not automatically as an Apple-exempt gift; if placed in-app, obtain a current Apple entitlement/policy determination or use a website-only route | Strong Romania fit for a solo developer who wants professional records and a separate work account |
| Revolut Business Payment Link | Hosted Revolut checkout; cards, Apple Pay, Google Pay, and other displayed methods | Merchant funds settle, generally within 24 hours; transfer from the Merchant account to the Revolut Business account, then use normal bank transfers | Same external-payment caution; most suitable for a legal entity or registered business | Use when the payee is a company or the volume/business setup justifies Business |
| Stripe Payment Link | Stripe-hosted page; fixed amount or customer-chosen amount, with available cards/wallets/payment methods | Stripe balance pays out to the connected bank account on its schedule; Romania is listed at 7 calendar days initial and 3 business days default settlement timing | Website-only is simplest. An actionable in-app external-payment link may require Apple’s EU entitlement/API path; a pure personal donation may also conflict with Stripe’s own policy | Good professional-service option; not first choice for a pure personal coffee gift |
| Website-only support page | User leaves the app voluntarily and uses the provider checkout on the developer’s site | Provider-specific payout flow | Lowest iOS integration risk, though App Store review still requires truthful app behavior and any in-app link must comply with current Apple rules | Recommended baseline; promote through website, release notes, email, or social channels rather than relying on an in-app CTA |

## How the providers work in Romania

### Stripe

Stripe’s global availability page lists Romania as a supported country. The Romania pricing page currently lists standard European Economic Area cards at **1.5% + 1.00 lei** per successful transaction; other card categories, international cards, currency conversion, and payment methods can have different rates. Stripe says there are no setup or monthly fees on standard pricing.

For a no-code button, create a Payment Link in the Stripe Dashboard. Stripe supports a “Customers choose what to pay” mode intended for donations, tipping, and pay-what-you-want: set a title/description, an optional suggested amount, and optional minimum/maximum values. The link opens Stripe’s hosted payment page. Dynamic payment methods can include cards, Apple Pay, Google Pay, and other methods enabled for the account, but the exact methods depend on the customer, browser, currency, and Dashboard configuration.

The important limitation is Stripe’s own “Requirements for accepting tips or donations” page:

* A **tip** must be given for a good or service that has been provided, such as content.
* A **donation** must be tied to a specific charitable purpose.
* Stripe does **not** support personal or peer-to-peer money transmission.

Consequently, call the payment a “tip/support for the app” only if it genuinely relates to an app or service already provided and the account/business description is accurate. Do not use Stripe to disguise a personal transfer as a charitable donation or generic P2P payment.

After payment, funds first sit in the Stripe balance. Stripe’s current payout documentation lists Romania at **7 calendar days initial settlement timing** and **3 business days default settlement timing**. The payout schedule can be automatic daily, weekly, monthly, or manual, subject to account settings and risk controls. The usual payout destination is the verified bank account in the Stripe Dashboard; Stripe lists Romania’s standard minimum payout amount as **5 RON**. Eligible Romanian accounts may also have Instant Payouts to a supported debit card, with Stripe currently listing a 2 RON minimum and 9,999 RON maximum, but this is eligibility-dependent rather than a guarantee.

### Revolut

There are two materially different paths:

1. **Personal Revolut.Me / payment request.** Revolut’s Romanian help documentation says the creator can choose a requested amount or share a generic `revolut.me` link where the sender chooses the amount. The sender may pay from a Revolut account or by card; the Romanian help page currently says Google Pay is not accepted for these personal payment links. Revolut’s personal terms describe the flow as sending or receiving money from a friend, so this is the most natural fit for a true optional personal gift but the least suitable for presenting a commercial checkout. The Romanian help page currently lists card-receipt limits that can be as low as £250 per week or £1,000 per month for a payment request, and `revolut.me` documentation lists a 250 GBP-equivalent weekly card limit plus transaction-count limits. Actual limits are account- and in-app-state dependent.

2. **Revolut Pro.** Revolut Pro is available in Romania as a separate professional work account inside the personal Revolut app. Revolut says it is for freelancers, side-hustlers, sole traders, and small solo ventures; it provides a separate IBAN and has no monthly Pro fee, while payment acceptance has per-transaction fees. For Romania, the current Pro page lists online Payment Links/Invoices at **1.20 lei + 1%** for domestic personal Visa/Mastercard, **1.20 lei + 1%** for Revolut Pay, and **1.20 lei + 2.8%** for international and commercial cards. Pro Payment Links can be sent by email, text, social media, or any other channel and can be reused or given a use limit.

   Pro payment funds can be transferred from the Pro account to an external bank beneficiary or to the developer’s personal Revolut account. Revolut’s separate help material warns that payment settlement timing can vary; its current Pro payment-timeline page says the first payout may have a seven-day waiting period and that 24-hour settlement can become available after qualifying payment history/checks. Do not promise instant withdrawal to users.

3. **Revolut Business.** Revolut Business requires a Business account and Merchant account. Its Romanian Payment Links page says customers use a secure Revolut-hosted checkout that can offer card, Apple Pay, Google Pay, and other available methods. The current Business pricing page lists online payments from **1% + 1.20 lei** for domestic/European consumer cards and **2.8% + 1.20 lei** for domestic commercial or international cards, with exact pricing subject to the account terms. Revolut says funds generally become available in the Merchant account within 24 hours, after which they can be withdrawn/transferred to the Revolut Business account without a withdrawal fee; currency conversion or other account fees can still apply.

For a Romanian solo developer, Pro is the practical professional option. Personal Revolut.Me is simpler if this is genuinely a gift. Business is the appropriate separation when the payee is a company or the activity is operated as a business. In every case, check the live in-app eligibility, payment-processing terms, chargeback rules, and account limits before publishing a permanent button.

## Apple App Store implications

### Native in-app tip

Apple’s current App Review Guidelines 3.1.1 state that apps may use in-app purchase currencies to enable customers to “tip” the developer or digital content providers. A conventional implementation is one or more **consumable** IAP products such as “Coffee,” “Supporter,” and “Large coffee,” with StoreKit presenting the App Store purchase sheet. The tip must not silently unlock a feature unless that feature is itself handled according to IAP rules. Configure the products in App Store Connect, implement StoreKit, test in Sandbox/TestFlight, and submit the first consumable IAP with an app version for review.

Apple’s App Store Connect documentation says receiving proceeds requires an active Paid Apps Agreement, bank information, the applicable minimum payment threshold, and any required invoicing steps. Once those requirements are met, Apple pays the primary bank account on file by direct deposit/EFT within 45 days of the last day of the fiscal month in which the transaction completed. Apple’s current threshold table lists Romania with a EUR bank-account threshold of USD 0.02; confirm the account’s actual bank currency and current App Store Connect state.

The exact commission depends on the agreement and program. Apple’s Small Business page currently describes a 15% rate for paid apps and IAPs for qualifying developers. Apple has also published new EU business terms updated 2026-08-18: the principal new terms are scheduled to take effect **2026-10-01**, and the EU payment page describes different future rates/commission structures. On 2026-08-27, do not assume that a future EU rate applies to the developer’s account; check which agreement the Account Holder has accepted in App Store Connect.

### External web payment link from the app

Apple’s general guideline 3.1.1(a) says that, outside the United States, an app generally may not include buttons, external links, or other calls to action directing customers to a non-IAP purchase mechanism unless the relevant entitlement and storefront rules permit it. The current EU-specific payment page says Romania is an eligible EU country for the StoreKit external-purchase/custom-link entitlement, but an actionable external offer requires the entitlement, StoreKit’s external-purchase API/disclosure flow, and compliance with Apple’s reporting, support, tax, and child-safety requirements. The page also describes a transition: the updated EU terms are available to accept now but the unified terms primarily take effect 2026-10-01.

For a link to a payment provider, this means:

* A simple `https://...` button in the Romanian App Store build should not be treated as automatically safe merely because Romania is in the EU.
* If the payment is for digital goods/services or is connected to receiving app content or functionality, use Apple IAP, or formally adopt the applicable EU external-purchase terms/entitlement/API before shipping the alternative flow.
* Under the current EU guidance, an actionable link invokes an Apple disclosure sheet and, for covered digital transactions, monthly transaction reporting. Apple’s page currently lists Store Services commission for out-of-app actionable offers and states that Apple may audit/report covered transactions. This is operationally much heavier than a website-only support page.

### Narrow personal-gift exception

Apple’s Guideline 3.2.1(vii) says an app may enable an individual user to give a monetary gift to another individual without IAP when the gift is completely optional and 100% of the funds go to the receiver. It immediately excludes gifts connected or associated at any point with receiving digital content or services, which must use IAP.

This is the strongest basis for an in-app Revolut.Me-style “optional gift to the developer” button, but it is a narrow policy exception, not a blanket permission for “donations.” Keep the wording and behavior aligned with all conditions:

* identify the recipient as an individual developer, not a company or anonymous fund;
* state that the gift is optional and provides no feature, content, priority, subscription, or other benefit;
* route 100% of the gift to that individual; and
* do not combine the gift with an app unlock, premium content, ad removal, cloud service, or other digital service.

Because Apple’s guideline is reviewed case-by-case and the app’s business model matters, include an App Review note explaining the exact gift flow and ask Apple Developer Support/App Review for written confirmation before relying on this exception for a prominent button. If the developer cannot satisfy all four conditions, use an IAP or keep the support link off-app.

## Romania tax and compliance boundary

The payment label does not decide the Romanian tax treatment. The current consolidated Fiscal Code text on the Romanian legislative portal says, in the rules for independent activities, that gross income includes amounts received from carrying out the activity, while amounts received as genuine donations are excluded from that independent-activity gross-income calculation. ANAF’s 2026 materials separately describe independent activities as production, commerce, and services and identify income from Romania and abroad as relevant to the annual tax declaration framework.

That does not establish that a payment called “coffee,” “tip,” or “donation” is tax-free. A payment that is economically consideration for app development, app content, support, or ongoing services may be business/professional income; a genuine gift may be analyzed differently. The correct result depends on facts such as recipient status (individual/PFA/company), whether anything is promised in exchange, frequency, public solicitation, records, VAT/CASS/CAS thresholds, and the provider’s statements/fees. The developer should retain provider reports, payout records, and a clear description of the flow and ask a Romanian accountant or tax lawyer before launch. This note is not tax or legal advice.

## Practical rollout recommendation

1. Decide which fact pattern is true: **personal gift with no benefit**, **professional tip for an app/service already provided**, or **payment that unlocks digital value**.
2. For a personal gift, create a personal Revolut.Me link and a short support page. Consider the in-app button only after Apple confirms the 3.2.1(vii) treatment; otherwise use the website and external communications.
3. For professional support, prefer Revolut Pro in Romania if a separate work account, local-friendly pricing, and direct bank transfer are useful. Use Stripe Payment Links if Stripe’s service-tip rules fit the business model and Stripe approves the account’s declared activity.
4. For any app-connected value or uncertainty about classification, use Apple consumable IAP tip tiers. Keep the IAP copy honest and make the product review notes explicit.
5. Before publishing, verify live provider fees, limits, settlement timing, payout bank details, refunds/chargebacks, and the Apple agreement/entitlement state. Recheck Apple’s EU page before the 2026-10-01 terms transition.

## Sources and access notes

All pages below were accessed on **2026-08-27**. Provider pricing, eligibility, payout timing, account limits, and Apple terms are dynamic; the linked live pages are the authority at implementation time. The findings use primary sources only, except that the Romanian legislative portal is the official publication/legislation source used for the Fiscal Code text.

### Apple

1. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — §§3.1.1, 3.1.1(a), 3.1.3, and 3.2.1(vii); accessed 2026-08-27.
2. [Payment options on the App Store in the EU](https://developer.apple.com/support/payment-options-on-the-app-store-in-the-eu) — EU entitlements, disclosure, reporting, commissions, and 2026-10-01 transition; accessed 2026-08-27.
3. [Changes for apps in the European Union](https://developer.apple.com/support/apps-in-the-eu) — EU alternative-payment availability and updated 2026-08-18 terms; accessed 2026-08-27.
4. [In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase) — StoreKit purchase processing and configuration overview; accessed 2026-08-27.
5. [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/) — App Store Connect product setup; accessed 2026-08-27.
6. [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/) — first consumable submission and App Review workflow; accessed 2026-08-27.
7. [Overview of receiving payments](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments/) — Paid Apps Agreement, bank details, threshold, and payment timing; accessed 2026-08-27.
8. [Minimum payment threshold](https://developer.apple.com/help/app-store-connect/reference/reporting/minimum-payment-threshold/) — Romania/EUR threshold table; accessed 2026-08-27.
9. [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) — qualifying 15% IAP/paid-app rate; accessed 2026-08-27.

### Stripe

10. [Stripe global availability](https://stripe.com/global) — Romania listed as a supported country; accessed 2026-08-27.
11. [Stripe Romania pricing](https://stripe.com/en-ro/pricing) — current Romania card pricing and standard account fees; accessed 2026-08-27.
12. [Create a Payment Link](https://docs.stripe.com/payment-links/create) — customer-chosen amount, hosted checkout, payment methods, and sharing; accessed 2026-08-27.
13. [Requirements for accepting tips or donations](https://support.stripe.com/questions/requirements-for-accepting-tips-or-donations?locale=en-GB) — tip/donation definitions and prohibition on personal/P2P money transmission; accessed 2026-08-27.
14. [Receive payouts](https://docs.stripe.com/payouts) — payout schedule, Romania settlement timing, minimum payout, and bank payout mechanics; accessed 2026-08-27.
15. [Instant Payouts for Stripe Dashboard users](https://docs.stripe.com/payouts/instant-payouts) — Romania eligibility and limits for eligible accounts; accessed 2026-08-27.

### Revolut

16. [Revolut Pro Romania](https://www.revolut.com/en-RO/revolut-pro/) — Romania availability, Pro account, Payment Links, and current Pro pricing; accessed 2026-08-27.
17. [What are Payment Links and how do I use them for Pro?](https://help.revolut.com/en-RO/help/more/revolut-pro/accepting-customer-payments/payment-links-and-how-to-use-them-for-pro/) — hosted checkout, sharing, and Pro Payment Link fees; accessed 2026-08-27.
18. [How can I transfer money out of my Revolut Pro account?](https://help.revolut.com/ro-RO/help/more/revolut-pro/move-money-out-of-my-revolut-pro-account/) — transfer to external bank or personal Revolut account; accessed 2026-08-27.
19. [What features are available with Revolut Pro?](https://help.revolut.com/en-RO/help/more/revolut-pro/features-available-with-revpro/) — separate IBAN and payment acceptance tools; accessed 2026-08-27.
20. [Revolut Business Payment Links](https://www.revolut.com/en-RO/business/payment-links/) — Business eligibility, hosted checkout, wallet methods, 24-hour settlement, and Business flow; accessed 2026-08-27.
21. [Revolut Business pricing and fees](https://www.revolut.com/en-RO/business/accept-payments-pricing/) — current Romanian online-payment rates and settlement note; accessed 2026-08-27.
22. [Methods to receive payments from customers](https://help.revolut.com/en-RO/business/help/merchant-accounts/payments/how-can-i-receive-card-payments-from-my-customers/) — Business Merchant account and online-presence requirement; accessed 2026-08-27.
23. [Revolut personal payment request links](https://help.revolut.com/ro-RO/help/adding-money/with-money-from-friends-or-relatives/requesting-money/) — amount selection, card/Revolut payment, limits, and current Google Pay limitation; accessed 2026-08-27.
24. [Revolut.Me link](https://help.revolut.com/ro-RO/help/transfers/payment-links/revolut-me-link/) — generic link, sender-chosen amount, and current limits; accessed 2026-08-27.
25. [Revolut Romania personal terms](https://www.revolut.com/en-RO/legal/terms/) — payment-link and Revolut.Me terms; accessed 2026-08-27.

### Romania

26. [Romanian Fiscal Code, Law 227/2015](https://legislatie.just.ro/Public/DetaliiDocument/239509) — independent-activity gross-income and donation-exclusion provisions; accessed 2026-08-27.
27. [ANAF: 2026 materials for annual tax declaration categories](https://static.anaf.ro/static/10/Iasi/material_informativ_25-02-2026.pdf) — independent activities/services and annual declaration context; accessed 2026-08-27.
28. [ANAF: 2026 annual income norms](https://static.anaf.ro/static/10/Anaf/AsistentaContribuabili_r/Normevenit2026/Norme_venit_2026.html) — current 2026 independent-activity tax-material context; accessed 2026-08-27.

## Evidence limits

* No provider account was opened and no live payment, payout, refund, chargeback, or App Review submission was performed.
* Apple’s interpretation of the individual-gift exception is ultimately an App Review/account decision; the recommendation above is a policy reading, not a guarantee of approval.
* Stripe and Revolut pricing/limits are quoted from live public pages and can differ by account, payment method, currency, risk review, and later terms changes.
* Romanian tax treatment was intentionally not resolved beyond the cited statutory/ANAF materials; obtain professional advice for the developer’s actual legal form and facts.
