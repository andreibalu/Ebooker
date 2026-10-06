# Unpaged — Support

_Last updated: October 6, 2026_

Unpaged is a free, private audiobook player for iPhone and CarPlay, built for iOS 18 and later. This page is the support hub — start here if something isn't working or if you have a question.

**Contact:** [andrei.baluta@yahoo.com](mailto:andrei.baluta@yahoo.com)

I read every message. Please include your iOS version and iPhone model so I can reproduce the issue faster.

## Frequently asked questions

### How do I add my own audiobooks?

Open Unpaged, tap **+**, and pick MP3, M4B, or AAC files from Files, iCloud Drive, or any provider connected to the Files app. Multi-file books import as a single audiobook with tracks ordered by filename.

If the selected files exactly match an audiobook already active in your library, Unpaged shows **Already in Library** instead of creating a duplicate. Renaming or moving the same files does not create another copy.

### Where do the free books come from?

The **Shelves** tab streams or downloads public-domain audiobooks from [LibriVox](https://librivox.org). Over 20,000 titles are cached locally for fast browsing. You can stream a book without downloading it, or download for offline listening.

The catalog is saved gradually in the background. Search and filters stay available while it is being prepared: title and genre searches can use LibriVox directly, while language and length filters also work on the books already saved. A notice identifies partial results until the full catalog is ready. Leaving the app pauses catalog preparation after the current page; returning resumes from the saved page.

Download progress stays visible in both **Shelves** and **Library**, even if you navigate away from the book. Downloads continue while Unpaged is suspended in the background and reconnect to their saved progress if iOS relaunches the app. You can cancel an active download or retry/dismiss a failed one from either tab.

On supported iOS versions, Unpaged also shows one download Live Activity on the Lock Screen. Compatible iPhones show the same progress in the Dynamic Island. Multiple book downloads are combined into one activity; tap it to open **Library → Downloads**. You can disable Live Activities in **Settings → Unpaged → Live Activities** without disabling background downloads.

At the top of the tab, **Collections** are hand-picked shelves of classics grouped by theme — for example Gothic & Horror, Detective & Mystery, or Short Listens you can finish in an afternoon. Every collection book streams, downloads, and samples exactly like the rest of the free catalog.

### Can I use my Audiobookshelf server?

Yes. If you run [Audiobookshelf](https://www.audiobookshelf.org) (or someone shares a server with you), open the **Shelves** tab, tap **Shelves** again to open the source menu, and choose **Audiobookshelf** — or go to **Settings → Audiobookshelf Server**. Enter your server address (for example `https://abs.example.com`) and either sign in with your username and password or paste an API key.

- **API keys** are created in Audiobookshelf under **Settings → API Keys**. A new key may need to be switched on there before Unpaged can use it.
- **Browsing:** Shelves shows your book libraries with **Continue Listening**, **Recently Added**, and the full library with search. If your server has several book libraries, tap the library name to switch. Podcast libraries aren't shown.
- **Listening:** tap **Play** on a book to add it to your Library as a streaming book and start listening. Nothing is downloaded, so your server has to be reachable while you listen. Your position is sent back to the server when you pause, leave the app, or finish, so other Audiobookshelf apps pick up where you left off.
- **Addresses:** both `https://` and plain `http://` addresses work, including servers on your local network (for example `http://192.168.1.20:13378` or `http://nas.local:13378`) and over a VPN such as Tailscale (for example `http://nas.your-tailnet.ts.net:13378` or `http://100.101.102.103:13378`). iOS will ask to allow **Local Network** access the first time you reach a server on your home network. If you enter a plain `http://` address for a server on the public internet, Unpaged warns you before signing in, because your password and listening activity would travel unencrypted; HTTPS (for example via a reverse proxy or Tailscale HTTPS certificates) is recommended for remote access. If a VPN address stops working, check that the VPN is switched on.
- **Privacy:** your login stays on this iPhone, in the Keychain. **Settings → Audiobookshelf Server → Disconnect** removes it. Books you added stay in your Library but won't play until you reconnect.

Removing an Audiobookshelf book from your Library only removes it from Unpaged; it stays on your server and you can add it again from Shelves.

### How do I navigate chapters?

Open the player and tap **Chapters** to jump to a chapter. The previous and next chapter buttons follow chapter markers embedded in supported M4B/M4A/MP3 files, chapter metadata supplied by Audiobookshelf, or individual tracks in a multi-file book. Files without chapter markers use one chapter per track. Audiobookshelf chapter metadata requires a reachable server.

### How do I change the app's appearance?

Open **Settings → Appearance** and choose **System**, **Light**, or **Dark**. Light and Dark apply regardless of your iPhone's appearance setting; System follows it. The choice also applies to sheets and onboarding and is remembered across launches.

### Can I choose a different narrator for a free book?

Often, yes. Many classics were recorded more than once by LibriVox volunteers. When other recordings of the same book exist, the book's detail page shows an **Other Recordings** section listing every alternative version in the same language — each with its length and a 20-second sample button that starts after the usual LibriVox intro so you can compare narrators before downloading. This works both from the Shelves tab and from a free book already in your library.

### Why don't covers load for some LibriVox books?

LibriVox cover URLs are inconsistent, so Unpaged intentionally generates a clean letter-template cover for every book in the free catalog. This is by design — your library stays visually consistent.

### What are the AI features?

Apple Intelligence (on-device only) powers two features:

- **AI Bookmarks** — when you save a moment, the app transcribes the audio around it and generates a name, a key quote, characters mentioned, and a mood tag.
- **AI Recap** — when you return to a book after a break, the app writes a short two-line recap of where you left off.

AI generation and transcription run entirely on your iPhone. If primary transcription fails, Unpaged can use Apple's older Speech fallback only when on-device recognition is supported. Audio and transcripts are not sent to speech servers, Unpaged, or any developer-operated server. First use may download Apple's on-device speech model for your language; once installed, the primary path works offline.

### Do AI features require a paid unlock?

Apple Intelligence moment naming and recaps are included with **Unpaged Plus**, an auto-renewing monthly (US$2.99) or yearly (US$14.99) subscription. Each plan includes a seven-day introductory offer when Apple makes it available to your Apple ID; the price and offer shown by Apple at purchase apply. Unpaged Plus also includes optional iCloud Sync. The rest of the app — playback, bookmarks without AI, library, Shelves, CarPlay, EQ — is always free. Existing AI Features unlock purchases remain recognized without expiration, and active legacy iCloud Sync subscriptions remain recognized while active.

### Which devices support the AI features?

The AI features rely on Apple Intelligence, which requires:

- iPhone 15 Pro / Pro Max, or any iPhone 16 (or later)
- Apple Intelligence enabled in **Settings → Apple Intelligence & Siri**

On iPhones running iOS 18–25, or on iOS 26 iPhones without Apple Intelligence, the AI buttons are hidden and the rest of the app works normally.

### Does Unpaged work in CarPlay?

Yes. Browse your library, play and pause, skip between tracks, and save bookmarks. Hands-free voice search lets you ask for a book by name while driving — say the title and Unpaged finds the match in your library.

### Does Unpaged work offline?

Anything you've downloaded plays offline, including LibriVox titles. Streaming-only library entries (including books from your Audiobookshelf server) and the LibriVox catalog browser require a network connection.

### How do I restore my purchases on a new device?

As long as you're signed in with the same Apple ID, Unpaged Plus and recognized legacy purchases reactivate through the **Plus** button (sparkles icon) at the top of the library → **Restore purchases**. You can change or cancel a Plus subscription from the same screen (**Manage Subscription**) or in your Apple ID subscription settings.

The optional **Buy me a coffee** purchase is a consumable tip. It has no entitlement and cannot be restored; you can buy it again whenever you want.

### Can I buy you a coffee?

Yes. Open **Settings → Buy me a coffee** to make an optional, one-time support purchase through the App Store. The price is shown in your local currency by Apple. It does not unlock features, add content, or provide any other benefit, and you can make the same purchase again later.

### How do I delete an audiobook?

Long-press the book cover in your library and choose **Delete**.

- **With iCloud Sync on**, this removes the audio from *this iPhone* but keeps the book in your **iCloud Library** — your progress, bookmarks, recaps, and equalizer settings stay safely backed up, and you can restore the book anytime (see "How do I restore my library" below). A book is only ever permanently erased from iCloud when you swipe to delete it inside your **iCloud Library** (**Plus** button at the top of the library → **iCloud Library**).
- **With iCloud Sync off**, you choose whether to remove the book from Unpaged only, or also delete its imported audio files from local storage. Nothing is backed up.

**Free books work the same way.** With iCloud Sync on, removing a free (LibriVox) book from your library keeps its progress and bookmarks in your **iCloud Library**. There are two ways to pick up where you left off:

- **Re-add it from the Shelves tab.** Because every free book carries its LibriVox ID, Unpaged recognises and reuses its iCloud record automatically, restoring progress, bookmarks, favorites, and equalizer settings whether you stream it or download it. It never creates a second copy of the same LibriVox recording.
- **From iCloud Library.** Tap the **Plus** button at the top of the library, open **iCloud Library**, find it under **Removed free books**, and tap **Stream**.

With sync off, removing a free book simply takes it out of your library; you can always add it again from the **Shelves** tab.

### Will my bookmarks and progress sync to other devices?

Yes — optional iCloud sync is included with Unpaged Plus, an auto-renewing monthly (US$2.99) or yearly (US$14.99) subscription billed through your Apple ID; prices vary by region. Both plans include a seven-day introductory offer when Apple makes it available to your Apple ID. Tap the **Plus** button (sparkles icon) at the top of the library to subscribe; you do not need to sign in to iCloud to purchase. Then sign in to iCloud and turn on **Sync library with iCloud** in **Settings → iCloud Sync**. The toggle controls the next launch: after either turning sync on or turning it off, quit and reopen Unpaged so its iCloud-backed store can be selected. Until relaunch, this launch keeps its existing sync state and its backup/delete behavior stays unchanged. Your titles, covers, progress, bookmarks (moments), recaps, equalizer settings, favorites, and listening-activity history then sync privately to the iPhones you're signed in to with the same Apple ID. The audio files themselves stay on each device — see the next FAQ. Cancel anytime in your Apple ID subscription settings; access continues through the end of the billing period. Everything else in Unpaged stays free.

### How do I know a book is backed up to iCloud?

When iCloud Sync is on, every book shows a small **iCloud checkmark** — on its cover in the library and as a "Backed up to iCloud" line on its detail screen. Subscribers with sync on also find an **iCloud Library** entry behind the **Plus** button at the top of the library (and under **Settings → iCloud Sync → iCloud Library**) showing a complete list of everything that's backed up. If you're not subscribed (or sync is off), the badge doesn't appear, because nothing is being backed up.

### How do I restore my library on a new iPhone (or after reinstalling)?

1. Sign in to the same iCloud account on the new device and install Unpaged.
2. Open **Settings → iCloud Sync → Sync library with iCloud**, turn it on, then quit and reopen Unpaged. Within a minute or two your library titles and metadata will appear.
3. Tap the **Plus** button at the top of the library and open **iCloud Library** to see **every book you've ever added** — nothing is hidden. Books are grouped so you can tell at a glance what's backed up and what's on this device:
   - **On this iPhone** — books whose audio is downloaded here (your own imports and downloaded free books). These show a checkmark; they're safe in iCloud and ready to play offline.
   - **Streaming** — free books and Audiobookshelf books you're keeping as streaming entries. No download, but fully backed up. Audiobookshelf books play again on a new iPhone once you connect the same server there.
   - **In iCloud only** — your own imports that synced down without their audio. Tap **Locate…**, pick the same audio file from Files / iCloud Drive, and Unpaged will fingerprint-match it. If the file matches, your bookmarks and progress flow straight back onto it. If it doesn't match exactly, Unpaged asks you to explicitly confirm adoption before replacing the cloud book's audio.
   - **Removed free books** — free books you removed from your library. Tap **Stream** to bring one back instantly, or open it and re-download for offline listening. Your bookmarks, progress, EQ, and recaps are already restored.
4. You can also just re-import a book the normal way (tap **+** in the library) — if the file matches an iCloud copy, Unpaged offers to restore it for you on the spot.
5. If you added a book as new and only later realized it has an older iCloud backup, open the book and tap the **iCloud** button in the top-right corner to pick the matching entry and pull its progress and bookmarks onto your copy. (The button appears only when iCloud Sync is on and there's a matching backup to merge into.)

Your iCloud Library keeps every book forever — it's only emptied when you swipe to delete a row inside the **iCloud Library**, which permanently removes that book from iCloud on all your devices.

## Troubleshooting

### A file I imported won't play

Make sure the file is in a supported format: MP3, M4B, or AAC. DRM-protected files (Audible `.aax`, Apple Books) are not supported — Unpaged cannot decrypt them.

### Playback stutters or skips on a downloaded book

Try closing and reopening the app. If the issue persists, delete and re-import the book — the underlying file may be corrupt.

### CarPlay voice search isn't working

Voice search needs Microphone and Speech Recognition permissions. Unpaged asks for both during the welcome flow on your iPhone — if you skipped that step or declined, go to **Settings → Unpaged** and enable them. The CarPlay screen itself cannot show permission prompts, which is why we ask on the iPhone first.

### Apple Intelligence isn't generating bookmark names

Confirm your iPhone supports Apple Intelligence (iPhone 15 Pro/Pro Max or any iPhone 16+) and that it's turned on in **Settings → Apple Intelligence & Siri**. The feature also requires the on-device model to be fully downloaded — this can take time after a fresh iOS install or update. The first AI bookmark or recap can be slower while iOS downloads its on-device speech model for your language; once installed, the primary AI path works offline.

### How do I manage the Unpaged Plus introductory offer?

The offer and renewal price for the selected monthly or yearly plan are shown by Apple before purchase. Manage or cancel it from the **Plus** button at the top of the library → **Manage Subscription**, or in your Apple ID subscription settings. Existing AI Features unlock purchases remain recognized without expiration; an older iCloud Sync subscription grants Plus while active.

## Privacy

Unpaged does not collect, sell, or share your personal data with the developer. Optional features communicate directly with Apple, LibriVox, and Internet Archive as described in the [Privacy Policy](https://gist.github.com/andreibalu/aca2af2e2176cc453175f708b2481262).

## Reporting a bug or requesting a feature

Email [andrei.baluta@yahoo.com](mailto:andrei.baluta@yahoo.com) with:

- A short description of what happened (or what you'd like to see)
- iOS version (Settings → General → About → Software Version, must be iOS 18 or later)
- iPhone model (e.g. iPhone 15 Pro)
- Unpaged version (shown at the bottom of the Settings sheet)
- Screenshots or a screen recording if relevant

Thanks for using Unpaged.
