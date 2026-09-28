# Unpaged — Privacy Policy

_Last updated: September 28, 2026_

Unpaged ("the app") is an audiobook player developed by Andrei Baluta. This policy describes what data the app handles and how. The short version: **Unpaged does not collect, sell, or share personal data with the developer, and the app has no backend server of its own.** Optional features communicate directly with Apple (iCloud, purchases, speech services, and system asset downloads) with LibriVox/Internet Archive (free-book browsing, streaming, and downloads), and — only if you connect one — with your own Audiobookshelf server. Unpaged never receives your name, email, or payment details.

## What stays on your device

Everything you create or import in Unpaged stays on your device unless you explicitly enable optional iCloud Sync. Local data includes:

- Audiobook files you import from Files or iCloud Drive
- Your library, favorites, playback progress, and finished/unfinished status
- Bookmarks ("moments"), notes, transcripts, AI-generated names and recaps
- Playback preferences (sort order, skip intervals, sleep timer, equalizer settings)
- Free-book downloads from LibriVox and the bundled catalog
- If you connect an Audiobookshelf server: its address, your username, and the sign-in token or API key, stored in the iOS Keychain on this iPhone (your password itself is not stored)
- In-app purchase entitlement state for Unpaged Plus and recognized legacy purchases. Apple processes subscription and introductory-offer eligibility; the optional coffee tip is a consumable purchase and does not create an app entitlement.

This data is stored in the app's private container on your iPhone. Unpaged does not upload it to any server controlled by the developer. Deleting the app removes the local copy; data previously synced to your private iCloud database remains there until you delete it through Apple's iCloud controls.

## Permissions Unpaged requests

| Permission | Why | What happens to the audio/data |
| ---------- | --- | ------------------------------ |
| **Microphone** | Hands-free voice search in CarPlay so you can ask for a book by name while driving. | Audio is passed to Apple's Speech framework for on-device transcription. If on-device recognition is unavailable for the selected language, recognition stops instead of sending audio to Apple's speech servers. Unpaged does not save the recording or send it to any developer-operated server. |
| **Local Network** | Reaching an Audiobookshelf server you connect that runs on your home network (for example `http://192.168.1.20:13378` or `http://nas.local`). iOS asks only when Unpaged first contacts such a server. | Unpaged talks only to the server address you entered. It does not scan or discover other devices on your network. |
| **Speech Recognition** | Converting CarPlay voice queries into text, and as a fallback for transcribing audiobook moments. | Apple's Speech framework performs recognition on-device. Unpaged requires on-device support and does not permit server-based Speech recognition. |

On iOS 26 and later, the AI features (moment naming and recaps) first use Apple's newer on-device speech engine, which does not require the Speech Recognition permission. Permission is requested only if the app falls back to the older Speech path. That fallback also requires on-device recognition support. If you decline these permissions, CarPlay voice search is disabled and fallback AI transcription cannot run. The rest of the app continues to work.

## iCloud Sync (optional, included with Unpaged Plus)

Unpaged Plus is an auto-renewing subscription that includes optional iCloud Sync and on-device Apple Intelligence features. Plus is offered monthly (US$2.99/month) and yearly (US$14.99/year), with a seven-day introductory free trial configured for each plan; prices and offer eligibility vary by region and Apple ID. Apple processes purchases and introductory offers through StoreKit — Unpaged never sees your payment information. When you enable sync, the app uses your **private** iCloud database (visible only to you) to keep your library aligned across the iPhones signed in to the same Apple ID. The data uploaded is:

- Audiobook titles, authors, cover art, and your favorite/finished flags
- Per-book progress, playback rate, equalizer state, and progress recaps
- Bookmarks ("moments"), including any transcripts, notes, AI-generated names, categories, moods, quote lines, and character lists you've captured
- Your listening-session history (per-day, per-hour aggregates) that powers the Reading Activity heatmap
- For free books: the LibriVox catalog ID and remote audio URLs so the book can be re-streamed or re-downloaded on another device
- For Audiobookshelf books: the server's item ID and the book's audio addresses on your server. These addresses never contain your sign-in token or API key, which stay in this iPhone's Keychain and are not synced
- For your own imports: a short content fingerprint (a SHA-256 digest derived from a small portion of each audio file) used solely to recognize the same file when you re-import it on another device

The audio files themselves are **never** uploaded — they stay on each device. Audio you imported continues to be local-only; on a new device you re-add the file and Unpaged matches it to the synced book record using the fingerprint described above.

Sync is off by default and is gated by an active Unpaged Plus or recognized legacy entitlement, your iCloud account on the device, and the Settings toggle. Purchasing Plus does not require signing in to iCloud; an iCloud account is required only to turn on sync. When sync is off (or you have no qualifying entitlement), Unpaged behaves exactly as the original local-only experience. The Settings toggle records your desired state for the next launch; the active iCloud/local store choice stays fixed until you quit and reopen Unpaged. This relaunch is required both after enabling and after disabling sync, so current-launch backup and deletion behavior cannot contradict its store. Once disabled after relaunch, Unpaged stops further uploads but does not delete previously synced data from your iCloud account. To delete the synced data, sign in to iCloud.com or System Settings → Apple ID → iCloud and remove the Unpaged data.

Apple's [iCloud privacy](https://www.apple.com/legal/privacy/data/en/icloud/) covers transport, storage, and access on Apple's side. Unpaged never sees a backend copy of this data — there is no Unpaged server.

## Apple Intelligence features

Unpaged uses Apple's on-device foundation model (Apple Intelligence) to generate moment names and progress recaps. AI generation happens **entirely on your device**. Primary transcription also runs on-device. If primary transcription fails, Unpaged's older Speech fallback runs only when on-device recognition is supported. Nothing is sent to Apple speech servers, OpenAI, Anthropic, or any developer-operated server.

The first time transcription runs, iOS may download Apple's on-device speech-recognition model for your language (a one-time download managed by the operating system, from Apple's servers). No audio or audiobook content is sent during this download — it only fetches the model. Once installed, primary transcription and AI generation work offline; the legacy Speech fallback also requires on-device support.

## In-app purchases

Unpaged offers two types of in-app purchases, both processed by Apple via StoreKit:

- **Unpaged Plus** — auto-renewing monthly and yearly subscriptions (US$2.99/month or US$14.99/year; prices vary by region) that include Apple Intelligence features and optional iCloud Sync. Each plan has a seven-day introductory free trial configured; Apple determines offer eligibility.
- **Buy me a coffee** — an optional one-time consumable tip. It does not unlock features, add content, or provide any other benefit. Consumable tips are not entitlements and cannot be restored; a user can purchase one again.

Previously purchased AI Features unlocks and active legacy iCloud Sync subscriptions continue to be recognized as Plus entitlements under their existing terms. Unpaged never sees your payment information, and no purchase data is sent to any third party. Apple's [Privacy Policy](https://www.apple.com/legal/privacy/) governs the purchase transaction.

## LibriVox content

Unpaged lets you browse and download free public-domain audiobooks from [LibriVox](https://librivox.org). When you search or download, your iPhone makes HTTPS requests directly to librivox.org and the audio hosts they link to (typically Internet Archive). LibriVox's privacy practices are governed by their own [privacy policy](https://librivox.org/pages/privacy/). Unpaged does not proxy or log these requests.

## Audiobookshelf (optional)

You can connect Unpaged to an [Audiobookshelf](https://www.audiobookshelf.org) server that you run or have an account on. Unpaged then talks **directly** to that server — there is no Unpaged server in between — to sign in, list your libraries and books, load covers, stream audio, and report your listening position back so the server (and your other Audiobookshelf apps) stay in sync. Your server's operator can see this activity the same way they see any Audiobookshelf client. The developer never receives any of it.

Your login is stored only in the iOS Keychain on this iPhone. When you sign in with a password, Unpaged exchanges it for a session token and does not keep the password. Books you add from your server are stored in your library without any credential; the token is attached only at the moment audio is requested. **Settings → Audiobookshelf Server → Disconnect** deletes the stored login. Books you added stay in your library (and, with iCloud Sync on, in your iCloud Library) but won't play until you connect again.

## Network usage

Network requests are made only:

- To LibriVox/Internet Archive when you browse, sample, or download a free book
- To stream a streaming-only audiobook you've added to your library
- To the Audiobookshelf server you connect, when you browse it, play one of its books, or pause/finish listening (to send your position back)
- To Apple iCloud when you enable iCloud Sync
- To Apple (App Store / StoreKit) for in-app purchase and restore
- Through Apple's Speech framework when CarPlay voice search runs or AI transcription uses the legacy fallback; Unpaged requires processing to stay on-device
- To Apple, once per language, when iOS downloads its on-device speech-recognition model the first time AI transcription runs (no audio or content is sent)

All requests use HTTPS, except that an Audiobookshelf server on your local network may be reached over plain HTTP if that is the address you enter. No analytics, ad networks, crash reporting SDKs, or third-party tracking are bundled in the app.

## Children

Unpaged is not directed at children under 13. We do not knowingly collect any personal information from anyone, including children.

## Changes to this policy

If this policy changes, the revised version will be posted at the same URL with an updated date. Material changes will be noted in the App Store version notes.

## Contact

Questions? Email **andrei.baluta@yahoo.com**.
