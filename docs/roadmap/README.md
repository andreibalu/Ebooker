# Unpaged UX & Feature Roadmap

Actionable, independently shippable vertical slices derived from a codebase-wide
UX audit of Unpaged `1.7.0`. Designed for execution with `$ship-feature` (configured
in [`.agents/ship-feature.md`](../../.agents/ship-feature.md)).

Run `$ship-feature` with no arguments to pick the next unchecked slice whose
dependencies are satisfied, or name a slice explicitly (e.g., `$ship-feature 03`).

## Slices

### Wave 1 — High-Confidence Fixes & Instant Daily Wins

| Status | Slice | Summary | Effort | Depends on | PR |
| --- | --- | --- | --- | --- | --- |
| [x] | [01 — Reading Stats Accuracy & Habit Loop](slices/01-reading-stats-accuracy-and-habit.md) | Fix midnight streak reset & 5-min avg-session bug; improve discoverability, interactive heatmap, daily goal, palettes, real covers & share card | M | — | [#102](https://github.com/andreibalu/Ebooker/pull/102) |
| [ ] | [02 — Moments Transcripts, Inline Metadata & Quote Sharing](slices/02-moments-transcripts-inline-and-sharing.md) | Search & display stored transcripts; show quotes/moods/tags inline on `MomentRow`; add quote card sharing & per-book Markdown export | M | — | — |
| [ ] | [03 — Smart Rewind, Cross-Track Skip & In-Player Undo Scrub](slices/03-smart-rewind-and-undo-scrub.md) | Pause-duration Smart Rewind (not once-per-launch), cross-track skip back, wire `jumpToSavedProgressMarker` as "Undo scrub", whole-book player context | M | — | — |
| [ ] | [04 — Sleep Timer Comfort](slices/04-sleep-timer-comfort.md) | Smooth audio fade-out on expiry, quick `+5/+15m` & shake-to-extend, custom duration picker, remember last timer, auto-rewind on expiry | M | — | — |

### Wave 2 — Everyday Listening & Audio Quality

| Status | Slice | Summary | Effort | Depends on | PR |
| --- | --- | --- | --- | --- | --- |
| [ ] | [05 — Universal Welcome-Back & Frictionless AI Opt-In](slices/05-universal-welcome-back-and-ai-opt-in.md) | Non-AI Welcome-Back card for all listeners after 3+ days away (layered with AI recap when eligible) + fix 3-toggle AI opt-in wall | S–M | — | — |
| [ ] | [06 — Equalizer Volume Boost Fix, Spoken-Word DSP & Global Defaults](slices/06-equalizer-dsp-and-audio-defaults.md) | Fix silent Volume Boost when EQ is off, drag-end persistence, Mono Downmix + Loudness Leveling in `EqualizerTap`, default Speed/EQ for new books | M | — | — |

### Wave 3 — Library Scale, Frictionless Import & Content Sources

| Status | Slice | Summary | Effort | Depends on | PR |
| --- | --- | --- | --- | --- | --- |
| [ ] | [07 — Library Book Search, Filters & Series/Shelves](slices/07-library-search-filters-and-series.md) | Unified Books + Moments search, Status/Offline/Source filters + Hide Finished, CloudKit-safe `seriesName`/`seriesSequence` & custom shelves | L | — | — |
| [ ] | [08 — Frictionless Local Import](slices/08-local-import-folders-open-in.md) | Folder selection in file picker, "Open in Unpaged" (`CFBundleDocumentTypes`), track reorder/exclude & cover picker in preview, async file copy | M–L | — | — |
| [ ] | [09 — Audiobookshelf & LibriVox Discovery Polish](slices/09-abs-and-librivox-polish.md) | ABS series links, progress/downloaded badges on all views, sort + narrator search, bookmark sync; LibriVox library badges, sort, Clear Filters & Wishlist | L | 07 (optional for series auto-fill) | — |

### Wave 4 — Native iOS 18 Surfaces & Hands-Free Polish

| Status | Slice | Summary | Effort | Depends on | PR |
| --- | --- | --- | --- | --- | --- |
| [ ] | [10 — iOS 18 Controls, CarPlay Library Search, Spotlight & Settings Polish](slices/10-ios18-surfaces-carplay-spotlight.md) | Control Center / Lock Screen `ControlWidget`s, silent widget Play/Pause, CarPlay library voice search & moment naming, CoreSpotlight, ABS download Live Activity, Settings Dynamic Type & essentials | L | — | — |

## Conventions

- **One PR per slice.** Keep diffs tightly scoped to the slice spec.
- **Update docs in the same PR:** Every behavior change updates its matching `docs/ios/*.md` file (and `support.md` / `privacy-policy.md` / `EULA.md` when required by `AGENTS.md`).
- **Mark progress on merge:** Check off `[x]` and record the PR number in the table above. When all slices in a roadmap finish, fold durable decisions into `docs/ios/` and prune obsolete slice docs per `AGENTS.md`.
