# Slice 6: Audiobookshelf source

## Behavior

Tapping the selected Shelves tab opens the Catalog source menu. It lists LibriVox and Audiobookshelf, marks the active source and shows "Connect your server" while disconnected. There is no separate source row. Choosing an unconfigured server
opens Connect. `UnpagedPreferences` owns `shelvesSource` and `absSelectedLibraryID`.
Disconnected or unknown source preferences resolve to LibriVox. Disconnect clears
credentials and selects LibriVox; it preserves streaming books in the local library.
Removing a server book deletes only its Unpaged row and app-owned files.

Connect supports username and password with `x-return-tokens: true`, or a Bearer
API key. Login validates the authorization endpoint before storing the connection.
Passwords and API-key drafts are never saved into activity instance state. The
screen uses the iOS header, field labels, connection states and inline errors,
with Android-specific storage and phone wording.

Private-host classification follows the iOS ranges, including CGNAT, IPv6 ULA,
link-local and loopback, local names and Tailscale names. Bare private hosts use
HTTP; bare Tailscale names use HTTPS unless an explicit port names a listener.
Public HTTP requires the same connection warning before sending credentials.
Acknowledgment belongs to that address in the current connect screen. Editing the
address clears it. The already-connected address skips the warning.

The client maps offline, unreachable, wrong-server, credential, inactive API key,
expired session and unreadable response failures. Unreachable errors explain the
same-network or VPN requirement; Tailscale addresses have the specific Tailscale
hint. A 401 session request shares refresh work with other requests and retries
once. A disconnected or replaced connection cannot be resurrected by refresh.

Browse loads book libraries, pages through their items and shows Continue
Listening, Recently Added for libraries larger than twelve books, and All Books.
The library picker persists its selection. Search filters titles and authors
locally, matching iOS. Covers use authenticated requests and generated-cover
fallbacks. Detail expands the item, displays author, narrator, duration,
description and server progress. It fills the page and hides the library header and tabs. The circular back control and system back return to browsing. The amber Play or Resume button adds a streaming row when needed. Add to Library changes to the checked "In your Library" status and removes the secondary button. Tapping that status opens the local row.

Browse places the server eyebrow directly below the tabs, with a bold serif library picker beneath it. Search uses a card-colored pill with a magnifier and italic serif placeholder. Section headers have a trailing hairline. Continue Listening covers have an amber progress bar and title and author labels. All Books uses a three-column cover grid. Server settings are reached through Settings, where the Sources card appears before Playback. The browse screen has no Server link.

Connect has a left-aligned Cancel pill, separate uppercase field labels and rounded card-colored fields. The server field precedes the underlined Sign in and API key choices. The full-width amber Connect button fades while disabled. The lock footnote explains Android Keystore storage. Server settings use a connected-host card, separate Server, Signed in as and Method rows, an amber Open in Shelves button and a centered Disconnect action.

## Storage and playback

Credentials use an app-private `noBackupFilesDir/abs-credentials.enc` file, atomic
replacement and AES-256/GCM with fresh Keystore-generated IVs. The key lives in
Android Keystore. Access and refresh tokens are encrypted together with the
server and user summary. No credential is stored in SharedPreferences or SQLite.
Existing backup rules exclude all app files, databases and preferences for both
cloud backup and device transfer; the credential directory is also excluded by
the platform. No security dependency was added. Key generation follows the platform
[KeyGenParameterSpec contract](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec).

SQLite schema v4 adds nullable `abs_item_id` and `abs_chapters_json` columns. The
migration preserves every prior table and row. ABS additions are streaming-only,
not free and not downloaded. Stored URLs must have the configured server origin
and contain no userinfo, fragment or credential query keys. Both the addition
boundary and SQLite insertion reject credential-bearing rows. Server progress
seeds the track-local position from its book-global time. Duplicate additions
reuse the existing book. Server chapters map onto track positions for player
navigation; ordinary books retain their prior chapter behavior.

Media3 resolves ABS URLs when opening the stream, appending the current token in
memory. Login sessions with less than 45 minutes remaining refresh first; API
keys never refresh based on expiry. Stored URLs and MediaItems remain token-free. Resolution uses
[Media3 ResolvingDataSource](https://developer.android.com/reference/androidx/media3/datasource/ResolvingDataSource.Resolver).
Progress PATCH payloads contain duration, book-global current time, fraction and
finish state. Reporting uses one ordered fire-and-forget queue on forced load, transition, pause,
background and finish persistence events. A disconnected or different-origin
server receives no update. Reporting failures do not interrupt playback.

The network security configuration intentionally permits cleartext HTTP for
self-hosted servers, matching iOS `NSAllowsArbitraryLoads`. Connect provides the
public-network warning. The `InsecureBaseConfiguration` lint advisory is
suppressed only on that explicit base policy. HTTP redirects are disabled for
credential-bearing API requests.

## Library card changes

The heart is 40dp with a 20dp icon. Its bottom-right offset overlaps the cover
edge onto the card. Its background uses a lightened cover tint so the part
outside the cover remains visible in both themes. Cards use a wider 12dp shadow with low-opacity ambient and
spot colors. Other component shadows and card content geometry remain unchanged.
Both themes have capture coverage.

## Verification

The deterministic stdlib server lives in `android/tools/fake-abs-server.py`.
`run-e2e.sh` generates the existing real WAV fixtures, starts this server and
stops it on exit. The emulator uses `10.0.2.2:13378`. The server implements login,
authorize, refresh, libraries, paged items, detail, authenticated covers, play,
range-capable WAV streaming and media progress. It records counts and progress
payloads, without recording tokens or URLs.

UI Automator journeys cover a wrong password and the full path through login, library picker, search, detail, add, playback, relaunch and disconnect. The playback journey asserts that the fake server received a tokenized stream request and a progress payload. A separate visual fixture uses the iOS fixture titles, authors, one chapter, a duration under one minute and 40% progress. The visual journey also checks the circular back button, system back, that detail hides the library header and tabs, and the state after adding.

Final run on 2026-10-07, on the dedicated `emulator-5580` with the full `tools/run-e2e.sh` command and no test filter: 101 of 101 host tests and 26 of 26 E2E journeys passed, with zero lint issues. Evidence is in `/private/tmp/unpaged-abs-e2e-final`.

The [visual report](visual-evidence/2026-10-07-abs/index.html) pairs Android captures with iOS captures of the source menu, connect, browse, detail and Settings. The iOS references came from the shipping app driven by the iOS fake ABS server. The iOS app's own appearance setting was Light during capture, so the iOS files named dark show light colors. Those pairs compare layout only, and the Android dark captures were reviewed on their own. Server settings and the added-detail state have no iOS capture and were compared against the SwiftUI source.

Expected differences: the emulator reaches the fake server at `10.0.2.2:13378` and iOS used `127.0.0.1`. Library counts follow each platform's fixture. The connect footnote names Android Keystore instead of the Keychain. Android has no Plus button. Fonts, native icons and system bars cause small offsets.

## Limits

This slice does not implement ABS downloads, offline catalog caching or a
replacement sync backend. Browsing needs a reachable server. Books remain in the
Library after disconnect and require a compatible server connection to stream.
Player, mini-player and notification artwork still use the existing generated
cover treatment. Fetched cover images are stored in the book's private folder. Generated covers remain
the fallback when the server supplies no readable cover. Android fonts, icons, dialogs and
system chrome differ from SwiftUI. Fake-server checks do not qualify a real ABS
installation, VPN or Tailscale routing, physical devices or a release build.
