# Audiobookshelf

Read this before changing the Audiobookshelf (ABS) source: the user's own server, offered in Shelves beside LibriVox. UI lives in `Views/Shelves/Audiobookshelf/`, view models in `ViewModels/ABSViewModels.swift`, the client in `Services/AudiobookshelfClient.swift`, and downloads in `Downloads/ABSDownloadManager.swift`. The [ABS API docs](https://api.audiobookshelf.org/) describe the server side.

## Source and account

- `BookSourceRegistry.sources` always lists ABS. Choosing it before connecting opens `ABSConnectView`. `isConfigured` follows `ABSAccount.shared`, and `ShelvesSourcePreference` falls back to LibriVox while ABS isn't connected.
- `AudiobookshelfClient` is an actor. Login sends `x-return-tokens`; API keys go as Bearer. A 401 on a login session triggers one refresh, shared by concurrent callers. Connecting with an API-key-shaped JWT that gets a 401 maps to `.inactiveAPIKey`.

## Tokens

Tokens live only in the Keychain (`ABSKeychainCredentialStore`).

- `AudioTrack.remoteURLString` for an ABS book is the token-less `storedStreamURL`. `AudioPlayerManager` adds `?token=` at play time through `playbackURL(forStoredURL:)`, which refreshes a login session close to expiry. It re-reads the connection after any await before appending the token, so a token never lands on another server's URL.
- `AudiobookshelfLibraryService.addToLibrary` refuses credential-bearing URLs; download manifests, the progress outbox and the response cache are token-free too. Anything new that stores an ABS URL stores it token-less.

## Item decoding

- `ABSMedia.playableTracks` prefers `tracks` and falls back to `audioTracks`. `expanded=1` item responses carry `tracks` with `audioTracks` null, while playback sessions carry `audioTracks`; reading only one key empties the list and add and download fail.
- The server sends empty strings where it means "none" (narrator, for example); the model treats `""` as nil.
- Series order comes from each book's top-level `sequence`. Numeric sequences sort numerically, fractions included; unnumbered books follow, by title. Collections keep server order.
- Person pages page through library items with `filter=authors.<id>` or `narrators.<name>`, base64-encoded with the URL-safe alphabet (a raw `+` would arrive as a space), scoped to the current library.

## Library rows

- ABS books have `isFreeBook == false` and keep `Audiobook.absItemID`, downloaded or not.
- **Remove Download** deletes local audio only. The row keeps progress, moments and EQ and returns to streaming.
- **Remove from Library** deletes the row, local progress included. Neither touches server content; the client has no DELETE call.
- Unload the book from the player before its files go.
- `OrphanDetectionService` checks every track file of a downloaded ABS book. A missing file (for instance a row synced from another device) returns the book to streaming; ABS books never become cloud-only orphans.
- Cloud Library files downloaded ABS books under On this iPhone and the rest under Streaming.

## Downloads

`ABSDownloadManager` runs its own background `URLSession`, separate from LibriVox's, with durable token-less JSON manifests.

- One track is in flight per job; progress and index matching depend on it.
- Partial audio stages in `Application Support/ABSDownloads/<job>/`. Finalize moves the folder to `Application Support/Audiobooks/<UUID>/` and promotes the existing row in place, so local playback and AI read the same paths as imported books.
- `didFinishDownloadingTo` moves the file synchronously, before returning; the system deletes it afterwards. The background completion handler runs (through `AppDelegate`) only after the file move and manifest write.
- The event drain type, `BackgroundEventDrain`, lives in `LibriVoxBackgroundDownloadCoordinator.swift`; both download systems depend on it.
- Cancel removes partial files and the manifest without promoting.
- The Library's pinned downloads section shows in-flight and failed ABS jobs. ABS downloads have no Live Activity.
- Settings (`ABSServerSettingsView`) shows downloaded size, removes all downloads, and on disconnect offers to keep or remove audio.

## Browse cache and offline

- Browse GETs are cached under Caches, scoped by server and username, with credential fields and URL tokens stripped. Caching is an allowlist of path prefixes inside `AudiobookshelfClient.request`; a new browse endpoint joins that list. Covers and streams bypass it.
- Only offline, unreachable and 5xx failures fall back to a saved response.
- Each screen load binds its own `ABSCacheUse` task local, which records whether any of its requests (`async let` children included) came from cache. Overlapping loads never share one. One cached response marks the whole screen offline.
- Offline screens show a banner and disable server actions; downloaded audio stays playable.
- Series and collection screens push `ABSGroupRoute` values whose destination is registered on `ContentView`'s `NavigationStack`. A destination declared inside the paged tab content never registers, and a view-destination link there loses its screen when the pager reloads.

## Progress sync

- `ABSProgressReporter` keeps the latest token-free, book-global position per item in a UserDefaults outbox. It flushes on connectivity, foreground, connect or refresh, and each new report.
- Before sending an entry it reads the server position and drops the entry when the server's `lastUpdate` is newer. A failed read keeps it queued; a permanent 4xx on send drops it. Disconnecting, or switching server or user, clears the outbox.
- Resume adopts the server position only when its `lastUpdate` is newer than both `Audiobook.absProgressWrittenAt` (or `lastPlayedAt` for rows saved before that field existed) and any pending report, and differs by more than a threshold. The check runs on a fresh load, or on resume after a long pause, with a short timeout and no token refresh; any failure counts as "nothing newer". Thresholds live in `AudiobookshelfLibraryService` and `AudioPlayerManager`.
- Re-adding a book that was removed creates a new row seeded from server progress.
- Local writes stamp the nullable `_absProgressWrittenAt` backing field, so a deliberate rewind wins by timestamp. Finish reports send `isFinished`.

## Plain-http servers

- `Info.plist` sets `NSAllowsArbitraryLoads` with `NSLocalNetworkUsageDescription`, so self-hosted servers work over LAN and VPNs such as Tailscale. iOS ignores `NSAllowsArbitraryLoads` when `NSAllowsLocalNetworking`, `NSAllowsArbitraryLoadsForMedia` or `NSAllowsArbitraryLoadsInWebContent` is also present; keep it the only ATS key.
- `AudiobookshelfClient.isPrivateNetworkHost` classifies private hosts (LAN, loopback, link-local, CGNAT, ULA, `.local`, unqualified names, `*.ts.net`). Plain http to any other host shows a one-time "isn't using HTTPS" confirmation in `ABSConnectView` before credentials are sent (`needsInsecureConnectionWarning`); the already-connected server skips it.
- An unreachable server maps to `.unreachableServer`, with a VPN/Tailscale hint for Tailscale hosts.
