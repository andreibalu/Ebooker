# Slice 3 — LibriVox Shelves (2026-10-06)

Implemented in the `android-shelves` worktree; iOS source in the main checkout and
`ios-reference-1.4.1/03-shelves-light.png` / `23-shelves-dark.png` are the references.
No iOS, player/mini-player, release metadata, GitHub issue or PR edits.

## Behavior and decisions

- Single production app module; no new dependencies. `LibriVoxClient` uses platform
  HTTPS, typed status/decoding errors, the exact catalog 404 no-match sentinel,
  HTTP-200 error envelopes, numeric/string feed fields, `extended=1`, and strict
  query encoding. IO/network exceptions remain distinct. Title/author searches
  merge and deduplicate; genre queries are separate because the feed cannot combine
  genre with title/author. Language and duration filter locally.
- `librivox-catalog.db` is separate from the user library, with metadata/track JSON
  and a transactionally committed sync cursor. Curated IDs match iOS. Preload finishes
  before 50-book paging; three transient attempts use 1s/2s backoff. Interrupted
  passes resume their original offset/since/start timestamp. Successful passes refresh
  after 24h using their start timestamp, avoiding changes missed during a long pass.
  No existing user schema changes or destructive migrations are needed: library v2
  already has catalog IDs, remote URLs and download state. Catalog v1 has an explicit
  upgrade guard; future changes must supply additive, tested migrations.
- A ViewModel coroutine syncs while the app/Shelves surface is active, pauses on
  background/disposal and resumes on return. Network callbacks update connectivity.
  This deliberately does not schedule background catalog work. Cached content,
  search and filters remain usable during preparation. Incomplete online search uses
  the live feed; unsupported language/length-only requests label partial saved results.
- Browse has the serif hero, one-based day ordinal modulo the curated list, primary
  filter labels with a 2dp amber selected underline, retry/status banners, collapsible
  collections, all six iOS collection ID lists, numbered chart and generated covers.
  `UnpagedPreferences` owns `librivoxCollectionsHidden` alongside the existing keys.
  Production chooses five classics once per visit; today's hero is excluded.
- Collections resolve cached IDs first, fetch only missing books, preserve curated
  ordering and degrade to an offline cached subset. Detail has HTML-to-text description,
  expansion, sample, streaming addition, download controls and cached Other Recordings.
  Known trailing recording suffixes strip repeatedly; translation suffixes remain.
- Streaming addition matches `catalogId`, marks free/streaming and stores token-free
  remote URLs without writing audio. Historical matches prefer downloaded then oldest.
  Promotion replaces only tracks/storage/download state in one transaction, preserving
  UUID, favorites, progress, moments and EQ. Library cards/details say **Streaming**.
- Session-owned downloads keep progress/cancel/retry/completion across navigation.
  Files stage in app-private `shelves-downloads/`, then move into `audiobooks/<UUID>/`.
  Cancellation/failure removes partial files; startup discards staging. A process-killed
  download retains its streaming identity and must be retried; byte-range download
  resumption and durable background download services are not implemented.
- Samples use an independent platform MediaPlayer, asynchronously prepare, seek to 30s,
  play for 20s after seek completion and release on stop/navigation/background. They
  check connectivity, request transient audio focus and do not depend on the main playback slice. Platform behavior:
  [MediaPlayer](https://developer.android.com/reference/android/media/MediaPlayer).

## Deterministic driver and release boundary

Only `src/debug/` contains `ShelvesFixtureActivity`, the `e2e-shelves-fixture` intent
extra, saved-only override and bundled fixture JSON. Launch that explicit debug
activity with the extra to seed the catalog. Normal relaunch preserves its saved-only
state. Clearing the app removes it. The fixture fixes Tale of Two Cities as hero and
Jane Eyre/Frankenstein/Pride version 2 as the first chart rows. The supplied dark iOS
reference has a different shuffled chart; Android keeps one order across theme changes.
Fixture track URLs permit adding cached streaming rows; forced offline prevents sample
or download traffic. This is not a live audio fixture/server qualification.

The existing real picker still imports the two user-library fixture equivalents and
sets the listening book's favorite. No debug bypass of local import was added.
The release variant's environment uses the real network/calendar/classic selection;
its APK must contain no fixture activity, intent marker or JSON asset.

Four added UI Automator journeys cover hero/collections/chart, search and all filters,
collection navigation, detail/description, offline retry/sample/download gates,
collection-collapse persistence, alternative navigation, Add → Library → force-stop
persistence and no repeated Add action. Driver capture names: `shelves-light`,
`shelves-dark`, `shelves-detail-light/dark`, `shelves-collection-light/dark`.

After the orchestrator runs the guarded suite, generate the focused comparison:

```sh
python3 tools/make-visual-report.py <captures> \
  ../docs/android/visual-evidence/ios-reference-1.4.1 <report-output> \
  --cases shelves-light shelves-dark
```

Only the two browse screens have supplied iOS capture counterparts. Review detail/
collection captures against SwiftUI source; do not mislabel library-detail screenshots
as catalog-detail references.

## Validation boundary

The slice instruction prohibits emulator E2E execution because Playback owns the
shared emulator. No emulator command, installation, screenshot or visual pass was
performed here. The orchestrator must run the compiled journeys after merging, review
light/dark captures and fix any visible differences. Compose typography, icons,
shadow/material behavior, search-field minimum height and system chrome still need
that review; this implementation is not a pixel-identical parity claim.

Host tests cover feed hardening, encoding, ordering/search merge, conservative
normalization, daily picks, SQLite cursor reopen/cache preservation, retry/resume/24h
refresh, streaming identity and promotion preservation. Actual feed completeness,
network reconnect/background transitions, sample timing/audio focus against the merged
main player, real download progress/cancel/retry, low storage, process interruption
and physical devices remain runtime qualification items. Sample/main-player interruption and restoration must be checked after merging;
this slice requests transient audio focus independently.


Final executed command (from the worktree root, with process-local JDK21/SDK exports):

```sh
./android/gradlew -p android --no-daemon :app:assembleDebug :app:lintDebug \
  :app:testDebugUnitTest :e2e:assembleDebug :app:assembleRelease
git diff --check
```

Result: BUILD SUCCESSFUL, **40/40 host tests** (20 new), zero failures/errors/skips,
**zero debug lint issues**. Debug app, E2E driver and unsigned release APK assemble.
15 E2E journeys compile; **0 executed**, **0 new captures**. Artifact inspection
confirmed the debug activity, intent marker and JSON asset present in debug and
all three absent from release. The report generator's Python syntax parses.
Evidence: `/private/tmp/unpaged-shelves-slice3-validation/` (build log, lint XML,
JUnit, HTML host report, APK digests and fixture-exclusion checks in `summary.json`).

Earlier iterations corrected a static Context lint report, a host-test import,
API28 SQLiteOpenHelper AutoCloseable casts (8/40 host failures in that iteration),
and an E2E UiScrollable compile error. No E2E failures/passes are claimed.


Commit attempt was blocked by the filesystem sandbox: Git could not create
`/Users/andreibalu/Developer/Ebooker/.git/worktrees/android-shelves/index.lock`.
Neither staging nor commit completed; changes remain on `codex/android-shelves`.
No push was attempted. The orchestrator must commit the validated source with
`Co-Authored-By: Codex <noreply@openai.com>` once shared Git metadata is writable.
