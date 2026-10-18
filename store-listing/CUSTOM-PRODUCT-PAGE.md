# Audiobookshelf custom product page

A second App Store page for people who already run an Audiobookshelf server. It shows the server library, the player resuming from the server's position, offline downloads, and series browsing, instead of the default page's LibriVox-first story ([custom product pages](https://developer.apple.com/app-store/custom-product-pages/)).

- **Name in App Store Connect:** Audiobookshelf users
- **Page id (`ppid`):** `0acf5796-9bc2-40d1-ac4a-eac2b3b583cb`
- **URL:** https://apps.apple.com/us/app/unpaged-audiobook-player/id6761081641?ppid=0acf5796-9bc2-40d1-ac4a-eac2b3b583cb
- **Version:** 1, created 2026-10-18 through the API. Read its state with `scripts/asc-api.sh GET /v1/appCustomProductPages/0acf5796-9bc2-40d1-ac4a-eac2b3b583cb/appCustomProductPageVersions`.
- **Localization:** en-US only. Other storefronts fall back to it, and the app UI is English.
- **Search keywords:** `audiobookshelf`, `offline`. A custom page can be associated only with words from the live keyword field ([Apple](https://developer.apple.com/app-store/custom-product-pages/)); see `NOTES.md` for the change needed when the next version's keywords ship.
- **Campaign link:** the `custom-page` row in `CAMPAIGN-LINKS.md`.

The page URL works only once Apple approves the page. Until then it opens the default page.

## Promotional text

Connect your Audiobookshelf server and listen on iPhone. Stream or download books for offline listening, browse series and collections, and keep your progress in sync.

## Screenshots (6.9" display, 1320 × 2868)

Uploaded as `APP_IPHONE_67`, the display type the API accepts for the 6.9" set (`docs/ios/release.md`). Apple scales the 6.9" set down for smaller iPhones.

1. **Audiobookshelf.** "Your server's library, on your iPhone." The Shelves tab connected to a server: Continue Listening with server progress, Recently Added.
2. **Listen.** "Pick up right where you left off." The player resumed at the server's saved position in a chaptered book.
3. **Offline.** "Download books for offline listening." The book page with its download.
4. **Browse.** "Series in reading order." A series page sorted by sequence.

## How the screenshots were made

They are real captures of the shipping 1.5.1 code (Debug build of `main` at `d9c1183`) on an iPhone 17 Pro Max simulator running iOS 27.0, with the status bar fixed at 9:41.

The library comes from `screenshots/abs-demo/`, a local demo Audiobookshelf server modeled on `e2e/support/fake-audiobookshelf.ts`: the same login and routes, with public-domain titles, typographic covers it renders itself, and chapter-length silent audio. No real narrators, covers or user data appear.

```sh
node screenshots/abs-demo/covers.mjs <scratch>/covers
node screenshots/abs-demo/server.mjs <scratch>/covers 13378 &
dns-sd -P "Unpaged demo" _http._tcp local 13378 audiobooks.local 127.0.0.1 &   # friendlier host name in the app header
# In the app: Shelves → Audiobookshelf → http://audiobooks.local:13378, user demo, password demo-password.
# Capture each screen with `xcrun simctl io <udid> screenshot`, name them as in compose.mjs, then:
node screenshots/abs-demo/compose.mjs <captures> <out>
```

`curl 'http://127.0.0.1:13378/__throttle?kbps=1500'` slows audio responses so a download stays visibly in progress.
