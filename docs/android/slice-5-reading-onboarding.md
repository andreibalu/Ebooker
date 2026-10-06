# Slice 5 — Reading activity and onboarding

Implemented under `android/` from the 2026-10-06 parity brief. iOS source in the
main checkout and the supplied `00-launch` / `22-favorites-dark` screenshots
were read as references. No iOS, release, tracker or emulator state was changed.

## Reading activity

The single app module and `LibraryStore` interface remain. SQLite schema **v3**
adds `reading_sessions` and a day/hour index through explicit `onUpgrade` steps.
No user table is dropped. Rows snapshot ID, title, author, public-domain status,
local calendar date, hour, minutes and creation time. They deliberately have no
book foreign key: removing a book preserves its listening history.

`ReadingSessionRecorder` runs on the existing playback controller's one-second
playing tick, counts wall time regardless of speed/seek position, emits at five
minutes, and flushes on pause, track transition, book load, background, removal,
finish and service detach. Under-30-second chunks are dropped; recorded minutes
round to the nearest minute with a minimum of one. Date/hour are captured at
chunk start, including chunks crossing midnight. Like iOS, an abrupt process
kill can lose the unfinished chunk (at most about five minutes).

Pure aggregates provide total time, sessions, average session, best day/hour/
weekday, current and longest streaks, book/author totals, books finished, and
public-domain share. Current streak requires activity today, as in the iOS
source. Favorites inserts ACTIVITY above its grid only with persisted activity;
it remains available if all books have been deleted. Tap opens the full stats
screen: adaptive heatmap, total/best day, clock, weekday histogram, longest-book
cover, streaks, metric cards, public-domain ring and Library return. Lazy section
reveals and number count-up honor Android's animator-duration setting; disabled
animations show final values. Typography uses Android serif where iOS uses serif.

`src/debug/.../ReadingActivitySeeder.kt` ports the iOS seeded 113-day distribution
and mulberry32 generator. It uses imported books first, classics only as fallback.
The explicit debug-only `ReadingFixtureActivity` accepts `e2e-reading-fixture`;
`reference=true` produces today's 42 minutes for the supplied Favorites capture.
It replaces synthetic session data only when invoked explicitly. Neither the
activity nor seeder exists in the release source/manifest. Imports stay real SAF
picker journeys; the fixture never inserts library books.

## Onboarding

Seven vertically paged scenes, a right progress-dot rail, a centered maximum
402dp content column, fixed text sizes, persisted completion and Reset Onboarding
in Settings → App. A small SharedPreferences wrapper remains the sole preference
owner. Completion uses `onboardingComplete`, recognizing legacy phase 3; resetting
only clears completion. Resume, skips and moment offset use the existing iOS keys.
Home choice writes `startOnFreeBooks` live and orders tabs Favorites/Shelves/
Library or Favorites/Library/Shelves. Completion lands on the chosen tab; later
launches preserve the existing shell's Favorites default for My books and Shelves
for the Shelves preference.

Intentional Android adaptations:

1. Start: same Shelves/My books copy and ordering.
2. Permissions: optional API33+ **notifications**, instead of microphone/speech.
   Denial is skippable. Previously denied permission can open Android app settings;
   grants are re-read on resume and advance only while this page is active.
3. Playback: live resume/skip/moment-offset controls and the same defaults.
4. Your year: explicitly labeled sample activity, never written to real stats.
5. Saved moments: manual timestamps; explicitly says AI naming/recaps are absent.
6. Your library: private local copies/offline downloads; explicitly says there is
   no cloud sync and uninstall removes app-owned data.
7. Done: live preference/permission summary, Open Library completes the flow.

No Plus, tip, purchase, iCloud or AI-purchase controls were introduced.

## Validation and handoff

From `android/`, with process-local JDK21/SDK exports:

```sh
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest :e2e:assembleDebug
```

The new black-box journeys compile only: first-launch onboarding/choice/live
settings/finish/relaunch/reset, seeded Favorites card/stats/relaunch. Existing
journey setup now completes onboarding through its visible controls. Guarded
runner approval/device checks are unchanged. **No E2E suite, install, emulator
command, or new Android capture was run**, per the parallel-slice restriction.

After integration, the emulator owner should run the guarded suite. Captures
specified in the journeys: onboarding-light/dark, activity-light/dark,
stats-light/dark. Compare the supplied reference pair with:

```sh
python3 tools/make-visual-report.py <captures> \
  ../docs/android/visual-evidence/ios-reference-1.4.1 <report> \
  --cases onboarding-light activity-dark
```

The report includes the unpaired source-derived dark onboarding/light activity/
stats gallery when present. No valid iOS light activity or full-stats capture was
supplied; these are source-derived checks, not invented reference pairs.

Remaining visual deviations: Android fonts/symbols/material surfaces; simplified
onboarding playback controls, sample-year/summary composition, stats section
spacing, streak ribbon, and no SwiftUI zoom/parallax transition. Host checks do
not establish exact visual parity, permissions on API33+, notification behavior,
background recorder execution, viewport fit, TalkBack, or device qualification.
The shared-emulator run and capture review must resolve those before parity signoff.

Final host result: **59 tests, 0 failures/errors/skips; 0 lint issues**; app and
E2E driver assembly succeeded. `git diff --check` and report-generator Python
syntax parsing passed. Evidence: `/private/tmp/unpaged-slice5-host` (build log,
JUnit XML/HTML, lint XML/HTML, validation counts and APK digests; no captures).
Initial iterations corrected a stale v2 assertion, the API28 test fixture's
unsupported SQLiteOpenHelper AutoCloseable cast (explicit close now), and two
strict Compose lint scroll-state reads (derived state now). No lint suppression
or baseline was introduced.
