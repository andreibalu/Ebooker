# Slice 4 — manual moments and per-book equalizer

Implemented in `android/` against the current read-only iOS source, with AI,
purchases, Plus/tips and cloud sync excluded. The single app module and
`LibraryStore` interface remain; SQLite v3 adds only `moments.is_pinned` with a
non-destructive v2→v3 migration. v1 installations upgrade through v2 and v3.
The existing SharedPreferences `UnpagedPreferences` owns the iOS-named
`momentBacktrackSeconds` key; no second preference store was introduced.

## Moments

Save Moment captures the book, track and `max(current time − Save Moment Offset,
0)` when opening **Name this Moment**. Done requires a nonblank name; Cancel
and dismissal leave storage untouched. Name, note, quote, category chips, mood
and character chips are editable. Characters trim whitespace and reject
case-insensitive duplicates. Draft metadata and open sheets survive activity
recreation. Successful saves use the existing SQLite metadata columns.

Detail shows singular/plural moment counts, pin/unpin, label, track-local time,
notes and category chips. Newest-first ordering puts pinned moments first.
The row and play button seek/play the captured track and time; the explicit
pencil opens editing. This follows the brief's row-tap playback requirement;
the newer iOS source opens editing on the row tap instead. Partial left swipes
reveal Delete, deliberate full swipes delete, and long-press offers Delete.
Category, mood and character filters expose only values present in the book;
selection is OR within a dimension and AND across dimensions. Clear All / Clear
Filters restores the list. Quote and character metadata remain editable in the
sheet, rather than cluttering the row.

## Equalizer

The player EQ action opens a medium/expanded sheet with the iOS copy, enable
card, Volume Boost, horizontally scrolling presets, five vertical manual
sliders and Reset to Flat. Configuration is saved to `equalizer_json` for the
bound book and reloaded when another book starts. Presets retain preamp and
enabled state; manual gain changes select Custom, selecting Custom retains the
curve, and reset retains enabled state while clearing gains/preamp.

Media3 1.8.0's service-owned audio sink always includes a PCM16
`EqualizerAudioProcessor`, even while disabled, so toggles and gains affect the
next buffer without restarting playback. Immutable volatile configurations
cross from UI to audio processing. Each channel has independent filter history;
flush/book/setting changes clear delays. The five RBJ peaking filters use Q=1,
±12 dB gains, 0–12 dB preamp, and the iOS rational soft limiter with a ±0.9 knee.
Disabling EQ bypasses both tone and boost. Bands at/above Nyquist bypass safely.
Float output is disabled so high-resolution decoded audio takes the PCM16 path.
See [Media3's processor pipeline](https://developer.android.com/reference/androidx/media3/exoplayer/audio/DefaultAudioSink.Builder#setAudioProcessors(androidx.media3.common.audio.AudioProcessor[])).

The brief explicitly specifies **60/250/1k/4k/14k Hz**; those frequencies and
labels are used. The newer iOS source uses **60/230/910/3.6k/14k Hz**, so this is
an intentional, documented deviation. All preset gain arrays match iOS.

## Validation and orchestrator handoff

From `android/`, with process-local JDK21 and Android SDK environment variables:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest :e2e:assembleDebug
```

Final result: APK and E2E driver compiled, **70 host tests passed, 0 failures,
errors or skips**, **0 app lint issues**. Sixteen new tests cover coefficient
response/identity/Nyquist, limiter continuity/oddness/bounds, channel isolation,
worst-case stability, PCM identity/live changes/reset, codec/preset semantics,
per-book EQ reopen and isolation, filters/characters, and v2→v3 metadata/pin
preservation. The prior v1 migration test now expects schema v3 and continues
to check preservation of an owned audio file. `git diff --check` passes.

Host evidence: `/private/tmp/unpaged-slice4-evidence/` contains the final Gradle
log, JUnit XML, lint XML/HTML and a count summary. Earlier failed iterations
caught a duplicate repository method, a Robolectric `AutoCloseable` fixture
cast, Compose mutable collection state and nullable draft saver typing; those
were corrected before the final successful run.

The separate UI Automator driver has **21 compiled journeys**, including three
new journeys for metadata save/edit/pin/filter/play/delete after force-stop,
blank/cancel/offset-clamp behavior, and EQ preset/boost/reset/per-book isolation
across relaunch. The existing playback save journey now completes the editor.
New capture names: `eq-light`, `eq-dark`, `save-moment-light`,
`edit-moment-dark`, `moments-light`, `moments-dark`, `moment-filters-light` and
`moment-filters-dark`. The report generator pairs `eq-light` with
`08-eq-light.png`; the other states have explicitly unpaired source-review
panels because no corresponding iOS references were supplied.

**E2E was not run and no emulator was touched**, as required by the shared
emulator boundary. There are no new screenshots or visual parity claims. The
supplied iOS EQ image was opened and inspected, and SwiftUI sources drove the
layout, but Android captures must be generated and reviewed by the orchestrator:

```sh
ANDROID_SERIAL=emulator-5580 E2E_EVIDENCE_DIR=/private/tmp/unpaged-slice4-e2e ./tools/run-e2e.sh
python3 tools/make-visual-report.py <android-captures> \
  ../docs/android/visual-evidence/ios-reference-1.4.1 <report-output> --cases eq-light
```

Remaining qualification: actual sheet geometry/touch/keyboard/rotation,
light/dark rendering, UI Automator selectors and swipe behavior, audible live EQ
and transitions on real codecs, output routes/offload/passthrough, and physical
phones. Compose/Android fonts, symbols, materials and system bars differ from
iOS; pixel-identical appearance is not established. Changes to filter
coefficients clear filter history at buffer boundaries; no parameter smoothing
or audible-click qualification is claimed. AI moment naming remains absent.
