# System surfaces

Read this before changing CarPlay, the Home and Lock Screen widgets, the Siri shortcut and App Intents, `unpaged://` links, or library moment search.

## CarPlay

- `CarPlaySceneDelegate` hands the scene to `CarPlayCoordinator`, which owns the templates, now playing, moment saving and the free-book lists (LibriVox search and the legacy seed catalog; see `free-books.md`). `AppDelegate` registers the CarPlay scene configuration and handles background URL session events.
- CarPlay can't embed SwiftUI, so its list rows use SF Symbol placeholders; now-playing artwork falls back to `GeneratedCoverView.renderImage`.
- `CarPlayVoiceSearch` dictates with the Speech framework and stops on silence or after a hard cap.
- **Permissions.** No permission prompt can appear on the CarPlay screen. `VoiceSearchPermissions.status` checks microphone and speech authorization synchronously, and voice search shows an info alert when either is missing. Permission requests belong in the iPhone onboarding flow (`onboarding.md`), never on a path that only CarPlay reaches.

## Widgets

The widget extension (`PagelessDownloadActivity/`) holds the download Live Activity and Continue Listening, which comes in small and medium Home Screen and rectangular and circular Lock Screen families.

- Continue Listening reads only `continue-listening.json` and a small cover JPEG from the `group.andreibaludev.Pageless` container, never SwiftData. The app writes them in `ContinueListeningSnapshotWriter` (encoder struct `Snapshot`); the widget decodes with its own `ListeningSnapshot`. The two types are separate copies: change both together.
- The writer runs on playback saves, pause, book change, finish and library removal. Periodic writes and timeline reloads are throttled, so widget progress can lag during play. Each write deletes every other `*.jpg` in the group container, so store nothing else as `.jpg` there.
- Generated artwork comes from `GeneratedCoverView.renderImage` in the app.
- Tapping a widget opens `unpaged://resume` (or `unpaged://library` when empty); the medium widget's play button runs `PlayLatestBookIntent`. DEBUG previews cover every family.

## Siri and App Intents

- `UnpagedAppShortcuts` (`AppIntents/AudiobookIntents.swift`) exposes "Play Latest Book" (`PlayLatestBookIntent`, compiled into the app and the widget) and "Save Moment" (`SaveMomentIntent`, app-only, `openAppWhenRun = false` so it works hands-free from the Action Button, Back Tap, Siri or Shortcuts).
- `PlayLatestBookIntent` can run in the widget process, so `perform()` writes the `intent.playLatestBook` flag to both `UserDefaults.standard` and the app-group suite, and posts a notification for a running app. `PagelessApp` consumes the flag at launch, on the notification and when `scenePhase` becomes `.active`. Each write and the notification serve a different entry path.
- `SaveMomentIntent` runs in-process through `SaveMomentAction.saveCurrentMoment` when `AppDelegate.shared` is live, applying `momentBacktrackSeconds`, naming via `MomentFallbackNamer`, attaching an optional Shortcut `note`, and falling back to the most recently played active book when nothing is loaded. It never queues a save for a later launch, because the moment would land at whatever position the player has by then. `PagelessApp` still consumes the `intent.saveMoment` flag on the pending-intent path; the E2E suite drives `SaveMomentAction` through it.

## Links

`UnpagedRoute` parses the `unpaged` URL scheme: `unpaged://resume` (play latest, through the same pending-intent path), `unpaged://library`, and `unpaged://library/downloads` (the Library tab's pinned downloads section).

## Library moment search

The magnifying glass in the library header opens `MomentSearchView` over every moment, archived and cloud-only books included. Matching happens in memory and needs no stored fields or network:

- Case and diacritics are folded, and every query word must appear (substring match).
- Moment name, book title and author outrank notes, quotes and the moment's tags (characters, categories, mood); ties go to the newest.
- `Moment.transcript` is searched too, at the lowest weight, so a spoken-word query finds a moment but never outranks a hit in its name, notes, quote or tags (an explicit tag beats a spoken mention). Smart save keeps the transcript even when naming falls back (`docs/ios/ai.md`), so this is what makes those moments findable by words nobody typed.
- When a query word matches only the transcript (no match in the moment's name, notes, quote, characters, categories or mood, nor in the book title or author the group header already shows), the row shows a snippet of at most two lines around the first match, with the match highlighted (`momentSearch.snippet.<label>`). A hit already visible in the row needs no snippet, and a transcript is never dumped whole into the list. The snippet logic is a pure function in `MomentSearch`, so the folding rules stay the same as for scoring.
- An empty query shows the most recent moments grouped by book.
- Rows reuse `MomentRow` and play through `playTrack(at:in:time:)`. A row whose audio is missing, whose server is disconnected or which needs the network while offline shows the reason and is disabled.

## Sharing a moment and exporting a book's moments

- **Share Moment** (row context menu, and the edit sheet's toolbar for an existing moment) shares a PNG quote card. **Export Moments…** (first row of a book's expanded moments list, beside Filter) shares one Markdown file per book. Both are `Transferable`s that hold only identifiers (`PersistentIdentifier` plus the `ModelContainer`) and short strings, because a `ShareLink` in a view body is rebuilt on every pass and the player publishes `currentTime` every second. The cover, the sorted tracks, the moment text, the render and the export date all resolve on the main actor inside the transfer closure, when the user shares. Keep any new share payload that cheap to construct.
- The edit sheet's card reflects the unsaved draft (name, note, quote) through `MomentQuoteCardDraft`, so it needs no save first.
- The card is deliberately light and fixed (explicit colors, Dynamic Type pinned) so the off-screen render never resolves dark-mode colors, and it never shows the transcript. Stored quotes may already carry quote marks, so `MomentQuoteText` strips them before the card and the row add their own.
- The Markdown export always includes transcripts. User text is escaped by `MomentMarkdownExporter` so it can't become structure: a leading block marker on any line is backslash-escaped, the user's line breaks stay as hard breaks, and `*`, `_`, backticks and brackets are escaped in headings and chapter lines. The file name collapses newlines and drops leading dots.
- The moments disclosure label holds only the count. A control inside a disclosure label squeezes the count at accessibility sizes and lends its accessibility id to the whole label, so Filter and Export sit in the content. The same goes for the edit sheet's Transcript disclosure: its id is on the label, never on the group.
- The row's metadata strip never truncates a chip: `ViewThatFits` tries three chips, then fewer, and folds the rest into "+N". The mood pill is in every variant.
