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

- `UnpagedAppShortcuts` (`AppIntents/AudiobookIntents.swift`) exposes "Play Latest Book", backed by `PlayLatestBookIntent` (`AppIntents/PlayLatestBookIntent.swift`, compiled into the app and the widget).
- The intent can run in the widget process, so `perform()` writes the `intent.playLatestBook` flag to both `UserDefaults.standard` and the app-group suite, and posts a notification for a running app. `PagelessApp` consumes the flag at launch, on the notification and when `scenePhase` becomes `.active`. Each write and the notification serve a different entry path.

## Links

`UnpagedRoute` parses the `unpaged` URL scheme: `unpaged://resume` (play latest, through the same pending-intent path), `unpaged://library`, and `unpaged://library/downloads` (the Library tab's pinned downloads section).

## Library moment search

The magnifying glass in the library header opens `MomentSearchView` over every moment, archived and cloud-only books included. Matching happens in memory and needs no stored fields or network:

- Case and diacritics are folded, and every query word must appear (substring match).
- Moment name, book title and author outrank notes and quotes; ties go to the newest.
- An empty query shows the most recent moments grouped by book.
- Rows reuse `MomentRow` and play through `playTrack(at:in:time:)`. A row whose audio is missing, whose server is disconnected or which needs the network while offline shows the reason and is disabled.
