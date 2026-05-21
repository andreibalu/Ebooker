# Unpaged — Support

_Last updated: May 21, 2026_

Unpaged is a free, private audiobook player for iPhone and CarPlay, built for iOS 18 and later. This page is the support hub — start here if something isn't working or if you have a question.

**Contact:** [andrei.baluta@yahoo.com](mailto:andrei.baluta@yahoo.com)

I read every message. Please include your iOS version and iPhone model so I can reproduce the issue faster.

## Frequently asked questions

### How do I add my own audiobooks?

Open Unpaged, tap **+**, and pick MP3, M4B, or AAC files from Files, iCloud Drive, or any provider connected to the Files app. Multi-file books import as a single audiobook with tracks ordered by filename.

### Where do the free books come from?

The **Free Books** tab streams or downloads public-domain audiobooks from [LibriVox](https://librivox.org). Over 20,000 titles are cached locally for fast browsing. You can stream a book without downloading it, or download for offline listening.

### Why don't covers load for some LibriVox books?

LibriVox cover URLs are inconsistent, so Unpaged intentionally generates a clean letter-template cover for every book in the free catalog. This is by design — your library stays visually consistent.

### What are the AI features?

Apple Intelligence (on-device only) powers two features:

- **AI Bookmarks** — when you save a moment, the app transcribes the audio around it and generates a name, a key quote, characters mentioned, and a mood tag.
- **AI Recap** — when you return to a book after a break, the app writes a short two-line recap of where you left off.

Both features run entirely on your iPhone. Nothing is uploaded.

### Do AI features require a paid unlock?

A free trial is included. After the trial, AI features are unlocked with a one-time purchase (no subscription). The rest of the app — playback, bookmarks without AI, library, free books, CarPlay, EQ — is always free.

### Which devices support the AI features?

The AI features rely on Apple Intelligence, which requires:

- iPhone 15 Pro / Pro Max, or any iPhone 16 (or later)
- Apple Intelligence enabled in **Settings → Apple Intelligence & Siri**

On iPhones running iOS 18–25, or on iOS 26 iPhones without Apple Intelligence, the AI buttons are hidden and the rest of the app works normally.

### Does Unpaged work in CarPlay?

Yes. Browse your library, play and pause, skip between tracks, and save bookmarks. Hands-free voice search lets you ask for a book by name while driving — say the title and Unpaged finds the match in your library.

### Does Unpaged work offline?

Anything you've downloaded plays offline, including LibriVox titles. Streaming-only library entries and the LibriVox catalog browser require an internet connection.

### How do I restore my AI purchase on a new device?

Open the **AI Settings** sheet inside the app and tap **Restore Purchases**. As long as you're signed in with the same Apple ID, the unlock will reactivate.

### How do I delete an audiobook?

Long-press the book cover in your library and choose **Delete**. This removes all associated files, bookmarks, and progress.

### Will my bookmarks and progress sync to other devices?

Yes — opt-in iCloud sync is built in. Open **Settings** inside Unpaged and turn on **Sync library with iCloud**. The first time you toggle it on you'll be asked to quit and reopen the app so the new iCloud-backed store takes effect. Your titles, covers, progress, bookmarks (moments), recaps, equalizer settings, favorites, and listening-activity history then sync privately to the iPhones you're signed in to with the same Apple ID. The audio files themselves stay on each device — see the next FAQ.

### How do I restore my library on a new iPhone (or after reinstalling)?

1. Sign in to the same iCloud account on the new device and install Unpaged.
2. Open **Settings → Sync library with iCloud** and turn it on. Within a minute or two your library titles and metadata will appear.
3. Open **Settings → Cloud Library** to see every book waiting to be re-acquired:
   - **Free books** — tap **Stream** to start listening immediately, or open the book and re-download for offline listening. Your bookmarks, progress, EQ, and recaps are already restored.
   - **Your own imports** — tap **Locate…**, pick the same audio file from Files / iCloud Drive, and Unpaged will fingerprint-match it. If the file matches, your bookmarks and progress flow straight back onto it. If it doesn't match exactly, you'll see a warning and can still adopt the file if you're confident it's the right book.
4. You can also just re-import a book the normal way (tap **+** in the library) — if the file matches an iCloud copy, Unpaged offers to restore it for you on the spot.

## Troubleshooting

### A file I imported won't play

Make sure the file is in a supported format: MP3, M4B, or AAC. DRM-protected files (Audible `.aax`, Apple Books) are not supported — Unpaged cannot decrypt them.

### Playback stutters or skips on a downloaded book

Try closing and reopening the app. If the issue persists, delete and re-import the book — the underlying file may be corrupt.

### CarPlay voice search isn't working

Voice search needs Microphone and Speech Recognition permissions. These are requested on the iPhone the first time you launch the app — if you declined, go to **Settings → Unpaged** and enable them. The CarPlay screen itself cannot show permission prompts, which is why we ask on the iPhone first.

### Apple Intelligence isn't generating bookmark names

Confirm your iPhone supports Apple Intelligence (iPhone 15 Pro/Pro Max or any iPhone 16+) and that it's turned on in **Settings → Apple Intelligence & Siri**. The feature also requires the on-device model to be fully downloaded — this can take time after a fresh iOS install or update.

### My free trial counter feels wrong

The AI trial tracks a fixed number of uses, not days. Restoring purchases or reinstalling does not reset the counter. If you believe the count is incorrect, email me.

## Privacy

Unpaged does not collect, transmit, sell, or share any personal data. Full details are in the [Privacy Policy](https://github.com/andreibalu).

## Reporting a bug or requesting a feature

Email [andrei.baluta@yahoo.com](mailto:andrei.baluta@yahoo.com) with:

- A short description of what happened (or what you'd like to see)
- iOS version (Settings → General → About → Software Version, must be iOS 18 or later)
- iPhone model (e.g. iPhone 15 Pro)
- Unpaged version (shown at the bottom of the Settings sheet)
- Screenshots or a screen recording if relevant

Thanks for using Unpaged.
