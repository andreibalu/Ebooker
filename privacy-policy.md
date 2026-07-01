# Unpaged — Privacy Policy

_Last updated: July 1, 2026_

Unpaged ("the app") is an audiobook player developed by Andrei Baluta. This policy describes what data the app handles and how. The short version: **Unpaged does not collect, sell, or share personal data with the developer, and the app has no backend server of its own.** Optional features communicate directly with Apple (iCloud, purchases, speech services, and system asset downloads) and with LibriVox/Internet Archive (free-book browsing, streaming, and downloads). Unpaged never receives your name, email, or payment details.

## What stays on your device

Everything you create or import in Unpaged stays on your device unless you explicitly enable optional iCloud Sync. Local data includes:

- Audiobook files you import from Files or iCloud Drive
- Your library, favorites, playback progress, and finished/unfinished status
- Bookmarks ("moments"), notes, transcripts, AI-generated names and recaps
- Playback preferences (sort order, skip intervals, sleep timer, equalizer settings)
- Free-book downloads from LibriVox and the bundled catalog
- In-app purchase entitlement state and the AI feature trial counter

This data is stored in the app's private container on your iPhone. Unpaged does not upload it to any server controlled by the developer. Deleting the app removes the local copy; data previously synced to your private iCloud database remains there until you delete it through Apple's iCloud controls.

## Permissions Unpaged requests

| Permission | Why | What happens to the audio/data |
| ---------- | --- | ------------------------------ |
| **Microphone** | Hands-free voice search in CarPlay so you can ask for a book by name while driving. | Audio is passed to Apple's Speech framework for transcription. Processing is on-device when supported; otherwise Apple may process it on its servers. Unpaged does not save the recording or send it to any developer-operated server. |
| **Speech Recognition** | Converting CarPlay voice queries into text, and as a fallback for transcribing audiobook moments. | Apple's Speech framework performs the recognition. Processing is on-device when supported; otherwise audio and transcripts may be sent to Apple under Apple's privacy terms. Unpaged has no server that receives them. |

On iOS 26 and later, the AI features (moment naming and recaps) first use Apple's newer on-device speech engine, which does not require the Speech Recognition permission. Permission is requested only if the app falls back to the older Speech path. If you decline these permissions, CarPlay voice search is disabled and fallback AI transcription cannot run. The rest of the app continues to work. Apple's [Siri, Dictation & Privacy](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/) notice explains when speech processing may occur on Apple's servers.

## iCloud Sync (optional, paid)

Unpaged offers an opt-in iCloud Sync feature, available as an auto-renewing monthly subscription (US$0.99/month; prices vary by region), that you can enable in Settings. The subscription is processed by Apple via StoreKit — Unpaged never sees your payment information. When on, the app uses your **private** iCloud database (visible only to you) to keep your library aligned across the iPhones signed in to the same Apple ID. The data uploaded is:

- Audiobook titles, authors, cover art, and your favorite/finished flags
- Per-book progress, playback rate, equalizer state, and progress recaps
- Bookmarks ("moments"), including any transcripts, notes, AI-generated names, categories, moods, quote lines, and character lists you've captured
- Your listening-session history (per-day, per-hour aggregates) that powers the Reading Activity heatmap
- For free books: the LibriVox catalog ID and remote audio URLs so the book can be re-streamed or re-downloaded on another device
- For your own imports: a short content fingerprint (a SHA-256 digest derived from a small portion of each audio file) used solely to recognize the same file when you re-import it on another device

The audio files themselves are **never** uploaded — they stay on each device. Audio you imported continues to be local-only; on a new device you re-add the file and Unpaged matches it to the synced book record using the fingerprint described above.

Sync is off by default and is gated by an active iCloud Sync subscription plus your iCloud account on the device. When sync is off (or you have no subscription), Unpaged behaves exactly as the original local-only experience. You can turn sync off at any time in Settings; doing so stops further uploads but does not delete previously synced data from your iCloud account. To delete the synced data, sign in to iCloud.com or System Settings → Apple ID → iCloud and remove the Unpaged data.

Apple's [iCloud privacy](https://www.apple.com/legal/privacy/data/en/icloud/) covers transport, storage, and access on Apple's side. Unpaged never sees a backend copy of this data — there is no Unpaged server.

## Apple Intelligence features

Unpaged uses Apple's on-device foundation model (Apple Intelligence) to generate moment names and progress recaps. AI generation happens **entirely on your device**. Primary transcription also runs on-device. If primary transcription fails and Unpaged uses Apple's older Speech fallback, Apple may process audio and transcripts on its servers when on-device recognition is unavailable. Nothing is sent to OpenAI, Anthropic, or any developer-operated server.

The first time transcription runs, iOS may download Apple's on-device speech-recognition model for your language (a one-time download managed by the operating system, from Apple's servers). No audio or audiobook content is sent during this download — it only fetches the model. Once installed, primary transcription and AI generation work offline; the legacy Speech fallback may still use Apple's servers when on-device recognition is unavailable.

## In-app purchases

Unpaged offers two in-app purchases, both processed by Apple via StoreKit:

- **AI Features** — a one-time non-consumable unlock.
- **iCloud Sync** — an auto-renewing monthly subscription (US$0.99/month; prices vary by region) that turns on cross-device sync.

Both are handled entirely by Apple's StoreKit. Unpaged never sees your payment information, and no purchase data is sent to any third party. Apple's [Privacy Policy](https://www.apple.com/legal/privacy/) governs the purchase transaction.

## LibriVox content

Unpaged lets you browse and download free public-domain audiobooks from [LibriVox](https://librivox.org). When you search or download, your iPhone makes HTTPS requests directly to librivox.org and the audio hosts they link to (typically Internet Archive). LibriVox's privacy practices are governed by their own [privacy policy](https://librivox.org/pages/privacy/). Unpaged does not proxy or log these requests.

## Network usage

Network requests are made only:

- To LibriVox/Internet Archive when you browse, sample, or download a free book
- To stream a streaming-only audiobook you've added to your library
- To Apple iCloud when you enable iCloud Sync
- To Apple (App Store / StoreKit) for in-app purchase and restore
- To Apple's Speech service when CarPlay voice search runs or AI transcription uses the legacy fallback; processing stays on-device when supported
- To Apple, once per language, when iOS downloads its on-device speech-recognition model the first time AI transcription runs (no audio or content is sent)

All requests use HTTPS. No analytics, ad networks, crash reporting SDKs, or third-party tracking are bundled in the app.

## Children

Unpaged is not directed at children under 13. We do not knowingly collect any personal information from anyone, including children.

## Changes to this policy

If this policy changes, the revised version will be posted at the same URL with an updated date. Material changes will be noted in the App Store version notes.

## Contact

Questions? Email **andrei.baluta@yahoo.com**.
