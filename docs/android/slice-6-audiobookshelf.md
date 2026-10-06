# Slice 6: Audiobookshelf source

## Behavior

Shelves always lists LibriVox and Audiobookshelf. Choosing an unconfigured server
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
description and server progress, then adds or opens its existing local row.

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

New UI Automator journeys cover a wrong password and the full login, library
picker, search, detail, add, playback, relaunch and disconnect path. Playback
asserts that the fake server received a tokenized stream and a progress payload.
Screenshots use `abs-connect`, `abs-browse`, `abs-detail` and `abs-library` with
`-light.png` and `-dark.png` suffixes. The report generator includes these as
source-review galleries because no ABS iOS screenshots were supplied. Existing
`library-light.png` and `library-dark.png` remain paired with the iOS references.

The full run on `emulator-5580` (`Unpaged_E2E_API35`) passed 25 of 25 UI
Automator journeys, including all 23 existing journeys. Host tests passed 101
of 101, including 27 ABS tests. Neither suite had failures, errors or skips.
The fake server recorded one tokenized stream request and six progress updates,
three with an advancing position. The runner stopped the server on exit.
No emulator was created, wiped or stopped.

Evidence is `/private/tmp/unpaged-abs-e2e`. The full runner initially exited with
one lint error in the final cover-tint accessor. Replacing `Bitmap.getPixel` with
the equivalent Kotlin `Bitmap.get` accessor was followed by a successful debug
build, all 101 host tests and lint with zero issues. The 25-journey run and its
screenshots precede that accessor-only change. Logs preserve both results.

The run used the requested JDK, SDK, serial and evidence directory. Writable
scratch Gradle, Android signing and Robolectric home directories were required
by the workspace sandbox, along with in-process Kotlin compilation.

The [visual report](visual-evidence/2026-10-07-abs/index.html) contains both
matching Library pairs and eight ABS captures. Heart placement and the broader
shadow were reviewed in light and dark mode. The ABS captures show generated
fallbacks as well as authenticated server covers. This is a human source and
screenshot review, not an automated pixel comparison.

## Limits

This slice does not implement ABS downloads, offline catalog caching or a
replacement sync backend. Browsing needs a reachable server. Books remain in the
Library after disconnect and require a compatible server connection to stream.
Player, mini-player and notification artwork still use the existing generated
cover treatment. Fetched cover images are stored in the book's private folder. Generated covers remain
the fallback when the server supplies no readable cover. Android fonts, icons, dialogs and
system chrome differ from SwiftUI. Fake-server checks do not qualify a real ABS
installation, VPN or Tailscale routing, physical devices or a release build.

## Changed files

Source and documentation paths are relative to the repository root. The visual
report is stored under `docs/android/visual-evidence/2026-10-07-abs/`.

- `android/README.md`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/dev/unpaged/android/SettingsScreen.kt`
- `android/app/src/main/java/dev/unpaged/android/UnpagedApplication.kt`
- `android/app/src/main/java/dev/unpaged/android/UnpagedPreferences.kt`
- `android/app/src/main/java/dev/unpaged/android/abs/ABSClient.kt`
- `android/app/src/main/java/dev/unpaged/android/abs/ABSCredentials.kt`
- `android/app/src/main/java/dev/unpaged/android/abs/ABSRules.kt`
- `android/app/src/main/java/dev/unpaged/android/abs/ABSScreens.kt`
- `android/app/src/main/java/dev/unpaged/android/library/LibraryModels.kt`
- `android/app/src/main/java/dev/unpaged/android/library/LibraryPresentation.kt`
- `android/app/src/main/java/dev/unpaged/android/library/LibraryScreen.kt`
- `android/app/src/main/java/dev/unpaged/android/library/LibraryStore.kt`
- `android/app/src/main/java/dev/unpaged/android/playback/PlaybackRules.kt`
- `android/app/src/main/java/dev/unpaged/android/playback/PlaybackService.kt`
- `android/app/src/main/java/dev/unpaged/android/playback/PlayerController.kt`
- `android/app/src/main/res/xml/network_security_config.xml`
- `android/app/src/test/java/dev/unpaged/android/abs/ABSTest.kt`
- `android/app/src/test/java/dev/unpaged/android/activity/ReadingMigrationTest.kt`
- `android/app/src/test/java/dev/unpaged/android/library/SQLiteLibraryStoreTest.kt`
- `android/e2e/src/main/AndroidManifest.xml`
- `android/e2e/src/main/java/dev/unpaged/android/e2e/LibraryE2ETest.kt`
- `android/tools/fake-abs-server.py`
- `android/tools/make-visual-report.py`
- `android/tools/run-e2e.sh`
- `docs/android/README.md`
- `docs/android/slice-6-audiobookshelf.md`
