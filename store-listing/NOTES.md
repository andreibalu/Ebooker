# Why the next-version metadata reads the way it does

Applies to the locale drafts in this folder. Delete this file with them once the version ships, after folding any rule worth keeping into `README.md`.

## Positioning

The live subtitle sells only LibriVox ("20,000 Free Classic Audiobooks"), while most people who search for an audiobook player already own audiobooks: M4B or MP3 files, or an Audiobookshelf server. The drafts lead with the three sources in this order: your own files, your Audiobookshelf server, free classics. Free iCloud Sync gets its own section because it removes the most common reason to pay for a player.

## How the App Store matches words

Apple indexes the app name, subtitle and keyword field together and combines words across them, so "player" in the name plus "m4b" in the subtitle already matches "m4b player". That shapes three rules ([Apple search guidance](https://developer.apple.com/app-store/search/)):

- **No repeats.** A word in the name or subtitle is wasted in the keyword field. `Unpaged`, `audiobook`, `player`, `offline`, `m4b`, `mp3` and `classics` are covered in en-US, so the keyword field leaves them out. Each locale's draft follows the same rule against its own name and subtitle.
- **Commas, no spaces.** Single words combine more freely than phrases, so two-word ideas are split (`sleep,timer`; fr `hors,ligne`; es `sin,conexión`).
- **No competitor names or unauthorized trademarks.** No Audible, Libby, Plex or BookPlayer. `audiobookshelf` and `librivox` stay because they name sources the app works with, which is how people search for a client. The description says what Unpaged does with them and never implies affiliation. Audiobookshelf asks for that spelling (or `audiobookshelf` / `ABS`) and no use of its name that suggests affiliation ([client guidelines](https://audiobookshelf.org/docs/faq/app/)).

## Subtitle choices

- en-US `Offline M4B, MP3 & Classics`: "offline", "m4b" and "mp3" are the words someone with their own files searches for; "classics" keeps the LibriVox audience. "Free" moved to the keyword field, where it still combines with "audiobook" and "classics".
- Localized subtitles put the local word for "player" first where the name doesn't already contain it (fr `Lecteur`, es `Reproductor`, it `Lettore`, pt-BR `Player`). de-DE's name already says `Hörbuch-Player`, so its subtitle spends the room on `offline`.

## Keyword choices

The words cover the remaining searches: sources (`audiobookshelf`, `librivox`, `server`), price (`free` and local equivalents), and the features people search for by name (`carplay`, sleep timer, chapters, bookmarks, widgets). Words for podcasts or ebooks stay out because the app doesn't support them. Every field is at most 100 characters and 100 UTF-8 bytes.

There is no search-volume data behind these choices yet. After the version ships, compare App Store Search impressions and downloads by locale in App Store Connect Analytics against the two weeks before, and change one field at a time.

## Promotional text

Promotional text doesn't affect search ranking and can change without review. Use it for news. The live 1.5.1 text (set 2026-10-18) describes the shipped app. The drafts here announce free iCloud Sync, so set them only once that version is live.

## Before submitting

- Check each claim against the build being submitted. Free iCloud Sync, audio in iCloud and the AI changes were still in flight when these drafts were written.
- Decide what existing iCloud Sync subscribers are told. The drafts drop the line about earlier iCloud Sync subscriptions because sync becomes free; the What's New doesn't address them directly.
- Update `support.md`, `privacy-policy.md` and `EULA.md` (and their Gists) for the purchase-terms and iCloud storage change, as `AGENTS.md` requires.
- The Audiobookshelf custom product page is associated with the live keywords `audiobookshelf` and `offline`. A custom page can only use words from the keyword field, and the en-US draft moves `offline` into the subtitle. Once the new keywords are live, check the page's keywords (`CUSTOM-PRODUCT-PAGE.md`) and associate `server` in place of `offline`.
