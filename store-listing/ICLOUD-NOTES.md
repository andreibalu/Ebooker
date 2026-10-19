# Store copy that must change when free iCloud sync ships

The release that ships free iCloud sync and audio in iCloud (PR `feature/free-icloud`) makes parts of the live App Store text wrong. Another agent owns the listing drafts. This note lists what must change, read from App Store Connect for version 1.5.1 on 2026-10-18. Delete it once the next version's drafts cover it.

## What changed in the app

- iCloud sync is free for anyone signed in to iCloud. It is opt-in, offered in the welcome tour and in Settings → iCloud Sync, and is no longer part of Unpaged Plus.
- Unpaged Plus now covers the Apple Intelligence features only (smart moment naming, recaps, future Plus features).
- New option: **Store audio in iCloud**. Imported books' audio can be stored in the user's iCloud Drive so another iPhone, or the same one after a reinstall, downloads the whole book from iCloud Library. It counts toward the user's iCloud storage. Free LibriVox and Audiobookshelf books are never stored, because they download again from their source.
- Earlier purchases are unchanged: an AI Features unlock is still permanent Plus, and an active legacy iCloud Sync subscription still counts as Plus while it lasts.

## Version localization (description), all six locales

Each locale's UNPAGED PLUS paragraph lists iCloud sync as a Plus feature, and a closing line says iCloud never syncs audio. Both are now wrong.

- **en-US**
  - Remove the Plus bullet "iCloud Sync for your library, progress, and moments across your iPhones".
  - Replace "Your imported audio stays on your device; iCloud Sync, if you turn it on, syncs library details and progress, never audio files." Suggested: "iCloud Sync is free: turn it on to sync your library, progress and moments, and optionally store your imported books' audio in your own iCloud storage."
  - Keep "Earlier AI unlock purchases and iCloud Sync subscriptions keep working."
- **de-DE, es-ES, fr-FR, it, pt-BR**
  - Remove iCloud sync from the Plus paragraph ("…und iCloud-Synchronisierung für Bibliothek, Fortschritt und Momente", "…e iCloud Sync para biblioteca, progreso y momentos", "…et la synchronisation iCloud de la bibliothèque…", "…e sincronizzazione iCloud di libreria…", "…e sincronização pelo iCloud de biblioteca…").
  - Add iCloud sync to each locale's list of free features.
  - Replace the closing "imported audio stays on your device; iCloud does not sync audio files" sentence with the free sync and optional audio storage above.
- **What's New** for the release should lead with free iCloud sync and the new audio option.
- Promotional text and keywords don't mention iCloud today. Adding "iCloud" to keywords is an option now that sync is free.

## Subscription metadata (owner's decision; not changed by this PR)

App Store Connect still describes the Plus subscriptions with iCloud:

- `andreibaludev.Pageless.plus.monthly`: "AI moments, recaps and iCloud Sync. Billed monthly."
- `andreibaludev.Pageless.plus.yearly`: "AI moments, recaps and iCloud Sync. Billed yearly."

These should drop "iCloud Sync", e.g. "AI moments and recaps. Billed monthly." Changing a subscription localization goes through review with the next version. This PR doesn't touch App Store Connect products. The local `Pageless/Configuration/Products.storekit` descriptions were updated to match the new scope.

The legacy "Unpaged iCloud Sync" group and its monthly product stay as they are: existing subscribers must keep it, and it is not sold.

## App Privacy

No change needed. Audio in iCloud goes to the user's own iCloud Drive, like the synced library in their private CloudKit database. The developer receives nothing, so "Data Not Collected" stays true. The privacy policy now describes audio in iCloud.

## Screenshots

Any screenshot or caption that shows iCloud under Plus, or the old Plus hub's iCloud Library row, is out of date.
