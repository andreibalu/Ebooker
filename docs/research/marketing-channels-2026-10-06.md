# Unpaged: marketing channels to test

**Date:** 2026-10-06, Europe/Bucharest. **Scope:** research and recommendations only. No outreach, advertising spend, App Store Connect changes, site changes, or app changes performed. Reddit publication is handled separately by the parent agent.

## Recommendation

Start with people who already have audiobooks and want an iPhone player. The clearest first audience is Audiobookshelf users. Give them a real demonstration, a useful setup guide, and a store page that shows the server integration. Then test local-file listeners and LibriVox listeners separately.

There is no channel-level acquisition or revenue evidence available in this research. The ranking below is a judgment about audience fit and cost, not a claim that these channels have already worked for Unpaged. Published platform capabilities establish what can be measured; they do not establish this app's ROI.

## Verified starting point

The Romanian storefront currently shows Unpaged 1.4.0, iPhone/iOS 18+, a subtitle centered on 20,000 classic audiobooks, and four ratings. Its description confirms local files, LibriVox, Audiobookshelf streaming with progress sync, free playback features, and optional Plus for on-device AI and iCloud Sync. ABS offline downloads are not advertised. The storefront privacy disclosure says Data Not Collected. These observations are territory-specific and are not worldwide adoption figures. [Current App Store listing](https://apps.apple.com/ro/app/unpaged-audiobook-player/id6761081641)

Local inspection of `site/src/pages/index.html`, `site/build.mjs`, and `site/site.config.json` shows an existing ABS section, English plus five translated home pages, canonical links, sitemap generation, and robots.txt generation. The public home URL could not be fetched by the web research tool; these are source observations, not proof of the currently deployed files. `screenshots/public/screenshots/en/05-shelves-audiobookshelf.png` already provides an ABS capture to reuse after checking it matches the shipping app.

## Ranked channels

| Rank | Channel and concrete next action | Why it is a good candidate | Estimated effort / cash | What would support continuing |
|---|---|---|---|---|
| 1 | Audiobookshelf ecosystem: prepare an entry for the official third-party app directory; use the existing Reddit update to answer real questions | Users already own the server and need a compatible client | 2–4 hours; $0 | Directory acceptance, real setup reports, attributed downloads and returning users |
| 2 | App Store conversion: prepare an ABS-specific custom product page; review search metadata and the first three screenshots | Makes the store destination match the reason people clicked | 4–8 hours; $0 excluding existing Apple membership | More relevant search/referral downloads and stronger conversion without weaker retention |
| 3 | Two practical setup guides with short screen recordings | Reusable answers to specific listener problems; useful in community replies and reviewer pitches | 6–10 hours; $0 | Search impressions/clicks and attributable installs; evaluate over 6–8 weeks |
| 4 | Small, relevant creator/reviewer outreach: shortlist five people who have actually covered ABS, self-hosting on iPhone, or audiobook apps | A demonstration can reach an audience already interested in the task | 3–5 hours; $0 initially | Testing replies, independent coverage and attributed downloads; follower count alone is insufficient |
| 5 | Apple featuring nomination tied to the next substantive update | Native design, on-device intelligence and independent developer story fit a credible editorial pitch | 1–2 hours; $0 | Editorial contact or actual featuring; treat as upside, not a predictable funnel |
| 6 | Apple Ads search results: a bounded exact-match experiment after the listing and measurement are ready | Measures demand close to an install decision | 2–4 hours setup; proposed $50 total test ceiling | Affordable acquisition that later produces paid customers and/or worthwhile retained listeners |

Effort and budgets are planning estimates, not quotes or measured results.

### 1. The directory is the most concrete overlooked opportunity

Unpaged was absent from the official ABS third-party apps directory when checked. The maintainers explicitly invite app creators to add their clients through a documentation PR. They require a stable, relatively mature client and ask maintainers to keep their own entry current. A listing is not an endorsement or a security review. [Official directory and submission instructions](https://audiobookshelf.org/docs/documentation/community/community-apps/), [source file for entries](https://github.com/audiobookshelf/audiobookshelf-docs/blob/master/src/components/CommunityAppsPage/communityAppsData.js)

Prepare a short factual entry: iOS, audiobooks, streaming, progress synchronization, username/password and API key. State streaming-only clearly. Do not label unsupported podcasts, OIDC, or downloads. Check the published client guidelines before submitting: describe compatibility without suggesting ABS affiliation, use its prescribed name spelling, and do not use its branding to encourage piracy. [Client app guidelines](https://audiobookshelf.org/docs/faq/app/)

The directory also links the official Discord. Investigate its current community rules before drafting any introduction. Answering a relevant user question is a better first interaction than pasting the same launch announcement everywhere. The user must review each new external post/message before it is sent.

### 2. Make the store page fit each audience

Prepare one custom product page for ABS users first: server library → player → progress synchronization. Keep the default page useful for the broader player/LibriVox audience. Apple supports custom screenshots, promotional text, previews, unique share URLs, and keyword associations for relevant search results. New assets need review, independently of an app update. Do not invent a product-page ID or deep link; configure real values later. [Apple custom product pages](https://developer.apple.com/app-store/custom-product-pages/)

The current title already identifies an audiobook player. Search topics to investigate include local M4B playback, offline listening, chapters, bookmarks, sleep timer, CarPlay, and equalizer. Search volume and the private live keyword field were not read, so no final keyword string is justified yet. Apple limits keywords to 100 characters and advises against repeating title/subtitle/category words or using competitor names and unauthorized trademarks. Promotional text does not improve search ranking. [Apple search guidance](https://developer.apple.com/app-store/search/)

Screenshots should demonstrate tasks, rather than list every capability. Avoid price and free-trial overlays in App Store screenshots; identify Plus requirements accurately when featuring Plus. Verify wording against current guideline 2.3.7 before preparing a submission. [Apple accurate-metadata rules](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)

Do not split a small audience across several A/B variants immediately. Apple product-page optimization supports one test at a time for up to 90 days and provides a traffic-based duration estimate. Use one meaningful screenshot treatment when volume is sufficient; wait for reliable confidence rather than declaring a winner after a handful of installs. [Product-page optimization](https://developer.apple.com/app-store/product-page-optimization/)

### 3. Publish useful demonstrations

Proposed guides, requiring a separate implementation/publishing step:

- **Listen to your Audiobookshelf server on iPhone with Unpaged.** Real connection steps, supported authentication, playback/progress demonstration, network requirements, and streaming-only limitation.
- **Play M4B and MP3 audiobooks on iPhone.** Import from Files, chapters, resume, bookmarks, and offline playback. Explicitly distinguish DRM-protected store purchases from compatible files.

Each should include a 20–40-second screen recording and one clear store link. Use your own narration or plain captions: one task, visible result. An AI recap demo can be a third asset after verifying it on supported hardware. Do not make AI the promise for every iPhone owner.

Google recommends helpful, original content grounded in first-hand experience, rather than many pages assembled mainly to attract search traffic. That supports writing two tested guides; it does not prove they will rank. [Google people-first content guidance](https://developers.google.com/search/docs/fundamentals/creating-helpful-content)

### 4. Pitch people who would actually use it

Build a five-person shortlist from recent relevant coverage; verify each person's contact route before drafting. Provide a short demo, store link, supported iPhone requirements, the ABS limitation, and enough information to reproduce the experience. Ask whether they want to try it, not whether they will publish a positive review.

MacStories is a credible editorial target because it covers Apple apps and tests reviewed apps personally; its stated policy rejects paid reviews. This establishes topical fit, not a likelihood of coverage. A niche self-hosting creator may fit the ABS audience more closely, but this research has not qualified named creators. [MacStories editorial policy and contact routes](https://www.macstories.net/about/)

An Apple featuring nomination can accompany the next meaningful release. Apple accepts nominations in App Store Connect and recommends advance notice; selection is discretionary. No nomination submitted here. [Featuring overview](https://developer.apple.com/app-store/getting-featured/), [nomination instructions](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/)

### 5. Paid ads are a later learning experiment

If paid testing is desired, choose one available storefront and a small group of descriptive exact-match terms, with Search Match off initially. Keep organic brand demand separate. Candidate terms such as “m4b player” and “offline audiobook player” are hypotheses; actual traffic and auction prices remain unknown. Apple Ads keyword reporting can identify terms delivering taps and installs. [Apple keyword management](https://ads.apple.com/app-store/help/keywords/0014-add-and-manage-keywords)

Proposed first experiment: five days at an average $10 daily budget, a fixed end date, and manual monitoring, giving a $50 ceiling under Apple's stated end-date budget rules. A daily budget alone is an average: individual days may exceed it, and campaigns otherwise continue monthly. No account or campaign was created. [Apple budget rules](https://ads.apple.com/app-store/help/bids-and-budget/0016-manage-budgets)

Low cost per install is not proof of profitable subscription acquisition. Compare actual proceeds after the trial and later renewals with spend. Without enough paying users, label the test inconclusive and do not scale it. No profitability threshold can be selected until paid conversion and retention are known.

## Measurement without adding a tracking SDK

Use App Store Connect Analytics, not RevenueCat. Generate a real campaign link for each new channel through ASC; use the actual provider token and unique campaign token rather than guessing a URL. Apple attributes first-time downloads within 24 hours of using the link. Metrics are only shown when their threshold of five is met, and campaigns appear after at least 24 hours. Missing campaign data can mean insufficient volume rather than zero response. Plain links in the already-approved Reddit posts cannot be retroactively campaign-tagged. [Apple campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)

Record source, territory, asset, publication date, hours spent, cash spent, first-time downloads, repeat usage, trials, paid conversion, and proceeds. Keep App Store Search, Browse, and referrals distinct. Usage/retention comes only from users who opted to share diagnostics and usage, so report the opt-in context and avoid treating it as the full population. [App usage and opt-in](https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage/)

Apple's displayed App Store conversion rate is total downloads/preorders divided by unique impressions. A separately computed first-time-downloads/product-page-views ratio is a different funnel measure and must be labeled as such. [Metric definitions](https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions)

## First two weeks

1. **Days 1–2:** record the prior two weeks' ASC baseline and territory mix, using the required ASC analytics integration. Prepare real campaign links for future channels. Collect setup questions from the two approved Reddit posts.
2. **Days 3–5:** prepare the ABS directory entry and compatibility notes, one actual 30-second demo, and the ABS-specific store-page storyboard. Show all proposed external text to Andrei before publishing.
3. **Days 6–9:** draft and verify the ABS setup guide; reuse its screenshots/video in tailored reviewer pitches. Qualify five reviewers/creators. Submit approved directory/store material only with scoped authorization.
4. **Days 10–14:** compare attributable downloads and opt-in usage with baseline, review actual questions/bugs, and prepare the local-file guide. Continue the channel producing useful returning listeners. Treat SEO as a longer experiment and the tiny initial cohorts as preliminary evidence.

Spend $0 on distribution in these first two weeks. The next decision is whether a measured $50 Apple Ads trial is worthwhile, not a broad paid social campaign. Generic Product Hunt launches, posting in many unrelated communities, and daily unspecific social updates are lower-priority hypotheses until the focused tests produce evidence.
