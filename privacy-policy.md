# Unpaged — Privacy Policy

_Last updated: October 17, 2026_

Unpaged ("the app") is an audiobook player developed by Andrei Baluta. This policy describes what data the app handles and how. The short version: **Unpaged does not collect, sell, or share personal data with the developer, and the app has no backend server of its own.** Optional features communicate directly with Apple (iCloud, purchases, speech services, and system asset downloads) with LibriVox/Internet Archive (free-book browsing, streaming, and downloads), and — only if you connect one — with your own Audiobookshelf server. Unpaged never receives your name, email, or payment details. Unpaged is available for iPhone and Android. Most of this policy describes the iPhone app; [Unpaged for Android](#unpaged-for-android) explains where the Android app differs.

## What stays on your device

Everything you create or import in Unpaged stays on your device unless you explicitly enable optional iCloud Sync. Local data includes:

- Audiobook files you import from Files or iCloud Drive
- Your library, favorites, playback progress, and finished/unfinished status
- Bookmarks ("moments"), notes, transcripts, AI-generated names and recaps
- Playback preferences (sort order, skip intervals, sleep timer, equalizer settings), including the welcome-back recap setting and device-local dismissal date for each book
- Free-book downloads from LibriVox and the bundled catalog
- If you connect an Audiobookshelf server: its address, your username, and the sign-in token or API key, stored in the iOS Keychain on this iPhone (your password itself is not stored)
- In-app purchase entitlement state for Unpaged Plus and recognized legacy purchases. Apple processes subscription and introductory-offer eligibility; the optional coffee tip is a consumable purchase and does not create an app entitlement.

This data is stored in the app's private container on your iPhone. The Continue Listening widget also keeps the last played book’s title, author, identifier, progress, time left, last-played date, and a small cover image in an on-device App Group container shared only with Unpaged’s widget extension. Unpaged does not upload it to any server controlled by the developer. Deleting the app removes the local copy; data previously synced to your private iCloud database remains there until you delete it through Apple's iCloud controls.

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

You can connect Unpaged to an [Audiobookshelf](https://www.audiobookshelf.org) server that you run or have an account on. Unpaged then talks **directly** to that server — there is no Unpaged server in between — to sign in, list your libraries and books, load covers, stream or download audio, and report your listening position back so the server (and your other Audiobookshelf apps) stay in sync. Your server's operator can see this activity the same way they see any Audiobookshelf client. The developer never receives any of it.

Unsent listening progress is kept locally as the latest item ID, server address, username, position, duration, finished status, and client timestamp. This queue contains no credentials and is cleared on disconnect or a server or user change. Unpaged retries delivery when connectivity returns, the app opens, or the connection refreshes, and reads server progress before resuming or sending a queued position to compare update timestamps.

Your login is stored only in the iOS Keychain on this iPhone. When you sign in with a password, Unpaged exchanges it for a session token and does not keep the password. Books you add from your server are stored in your library without any credential; the token is attached only at the moment audio is requested. **Settings → Audiobookshelf Server → Disconnect** deletes the stored login. Books you added stay in your library (and, with iCloud Sync on, in your iCloud Library). Disconnect asks whether to keep or remove downloaded audio. Kept downloads play offline; streaming requires reconnecting.

Server library lists, series and collections with their book order, author and narrator browsing results, book metadata, item details, and listening positions are cached under this iPhone's Caches directory for offline browsing, separately for each server and username. These caches contain no login tokens or API keys and may be cleared by iOS. Downloaded audio stays in Application Support; background download manifests store only token-less audio addresses and transfer status. Audio files do not sync through iCloud. Remove Download deletes the local audio while keeping library metadata, progress, moments, and EQ. Downloaded books can use the same on-device AI processing as imported books.

## Network usage

Network requests are made only:

- To LibriVox/Internet Archive when you browse, sample, or download a free book
- To stream a streaming-only audiobook you've added to your library
- To the Audiobookshelf server you connect, when you browse it, stream or download audio, or pause/finish listening (to send your position back)
- To Apple iCloud when you enable iCloud Sync
- To Apple (App Store / StoreKit) for in-app purchase and restore
- Through Apple's Speech framework when CarPlay voice search runs or AI transcription uses the legacy fallback; Unpaged requires processing to stay on-device
- To Apple, once per language, when iOS downloads its on-device speech-recognition model the first time AI transcription runs (no audio or content is sent)

All requests use HTTPS, except that an Audiobookshelf server may be reached over plain HTTP if that is the address you enter (common for servers on a home network or a VPN such as Tailscale). If you enter a plain HTTP address for a server on the public internet, Unpaged warns you before signing in that your login and listening activity would be sent unencrypted. No analytics, ad networks, crash reporting SDKs, or third-party tracking are bundled in the iPhone app.

## The Unpaged website

The website (the marketing pages and these documents) uses no cookies, analytics or geolocation. To show the current sky behind its header, your browser sends one request to [Open-Meteo](https://open-meteo.com) with an approximate location: coordinates for a city in your browser's time zone, not your actual position. The request carries no identifier and no referring page. The weather that comes back is kept only in your browser's session storage for up to 30 minutes and is gone when you close the tab. If the request fails, the sky follows your device's clock instead. Open-Meteo's handling of requests is covered by its own [terms and privacy policy](https://open-meteo.com/en/terms).

## Unpaged for Android

The Android app offers the same local library, LibriVox, Audiobookshelf, moments, equalizer, and Reading Activity features, with these differences.

**No purchases or iCloud.** The Android app has no subscriptions, tips, or in-app purchases, and no iCloud Sync. Every feature is free.

**Permissions.** Android asks only for permission to show notifications (Android 13 and later), used for playback controls and download progress. Declining it never blocks playback. Unpaged for Android does not request microphone or speech-recognition access. Android Auto voice search is handled by Google Assistant, which passes Unpaged only the text of your request.

**Where data is stored.** Your library, progress, moments, settings, and Reading Activity live in the app's private storage on your phone. Imported audio is copied into that storage; your original files are never modified or deleted. Audiobookshelf sign-in details are encrypted with a key held in the Android Keystore and are never included in backups.

**Android backup (optional).** When the in-app Back Up Library setting and your phone's backup service are both on, Android's backup system (for example Backup by Google, stored in your Google account) saves a copy of your library list, progress, moments, and settings, and can restore it on a new phone or after reinstalling. Audio files, covers, the LibriVox catalog cache, AI recaps, downloaded models, and Audiobookshelf credentials are excluded. Unpaged never sees this backup; Google's [Privacy Policy](https://policies.google.com/privacy) governs it. Turning off Back Up Library in Settings stops cloud backup of Unpaged; a direct phone-to-phone transfer during new-phone setup still copies the library.

**On-device AI (optional, off by default).** On phones that support Gemini Nano, Unpaged can name moments and write recaps. Text generation uses Gemini Nano on your phone through Google's ML Kit GenAI Prompt API, and speech-to-text runs on your phone with the open-source Whisper model. Your audio, transcripts, prompts, and results are never sent to any server. The Whisper speech model (about 60 MB) is downloaded from Hugging Face (huggingface.co) only after you agree; that download sends a standard web request, which reveals your IP address to Hugging Face, and no audio or content. You can delete the model in Settings. Gemini Nano itself is installed and updated by Android, not by Unpaged.

**Google ML Kit diagnostics.** The ML Kit library behind Gemini Nano sends Google diagnostic and usage information so Google can maintain it: device model and Android version, app package name and version, per-installation and device identifiers, performance metrics, error codes, configured language, and the size (not the content) of AI requests and results. This is sent over HTTPS, is not shared with third parties by Google, and is not used for advertising. It never includes your audio, books, moments, or generated text. See Google's [ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure). Apart from this library, the Android app bundles no analytics, ad networks, crash-reporting SDKs, or tracking.

**Network usage.** The Android app connects only to LibriVox and Internet Archive (browsing, samples, streaming, downloads), the Audiobookshelf server you connect, Hugging Face (the one-time speech model download), and Google through ML Kit as described above. As on iPhone, a plain HTTP Audiobookshelf address is allowed, and you are warned before signing in to one on the public internet.

**Deleting your data.** Uninstalling Unpaged deletes everything it stored on your phone. To remove a backup, delete it from your Google account's backup settings.

## Children

Unpaged is not directed at children under 13. We do not knowingly collect any personal information from anyone, including children.

## Changes to this policy

If this policy changes, the revised version will be posted at the same URL with an updated date. Material changes will be noted in the App Store and Google Play release notes.

## Contact

Questions? Email **andrei.baluta@yahoo.com**.
