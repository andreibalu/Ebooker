# Slice 01 notes (temporary; delete before merge)

DECISIONS TAKEN for slice 01 (after decision review by Opus 5.5 high + Gemini 4 Neon high):

D0 (new). Recorder credits WALL-CLOCK time. Today ReadingSessionRecorder adds a fixed 1 s per tick of AVPlayer's periodic observer, which fires per 1 s of MEDIA time (AudioPlayerManager.swift ~1039), so at 2x speed minutes are doubled, contrary to ReadingSession.minutes' doc ("Wall-clock minutes"). New behaviour: the recorder measures real elapsed time between ticks (monotonic clock, e.g. ProcessInfo.systemUptime or ContinuousClock), capped at 3 s per tick so a stall/background gap never credits a lump; first tick after start/flush credits 1 s. Old rows are left as they are. Also: when the book being played changes in AudioPlayerManager.load(), call sessionRecorder.flush (synchronously, before the first await) so book A's chunk is stamped when it actually ended. Update docs/ios/playback.md line about "credits a fixed amount per tick".

D1. Session coalescing, NO schema change (rejected: synced `_sessionGroupID`). In ReadingStats.compute:
  - A row's createdAt is "usable" if createdAt != distantPast AND its estimated start (createdAt − minutes·60) lies within ±75 min of the bucket instant (date + hour·3600). Otherwise the row is "untimed".
  - Timed rows: sort by (createdAt, id). Row i joins the previous row's logical session if same bookID AND createdAt_i − createdAt_{i−1} ≤ 2·minutes_i·60 + 180 s (negative gaps allowed; tolerates 0.5x–3x old book-time rows, rounding, the dropped <30 s flushes).
  - Untimed rows: sort by (dayKey, hour, id); join previous untimed row if same bookID, same dayKey, and hour equal or +1.
  - Timed and untimed rows never join each other.
  - totalSessions = number of logical sessions; avgSession = totalMinutes / totalSessions.
  - Do not trust input order (the @Query sorts by date only).
  - ReadingActivitySeeder and E2E fixtures set realistic createdAt = date + hour·3600 + minutes·60 (use calendar.date(byAdding:), not −86_400 arithmetic).

D2. Streak grace. currentStreak counts back from today if today has activity; else from yesterday if yesterday has activity; else 0. Unbounded backward loop (not limited by daysTracked). A dayKey later than today (timezone travel west) counts as today. New `isStreakActiveToday: Bool`. longestStreak unchanged. `ReadingStats.empty` becomes `static func empty(today: Date = .now, calendar: Calendar = .current)`. The stats `today` must refresh: views hold today in @State and update it on .NSCalendarDayChanged and UIApplication.significantTimeChangeNotification. Copy: card (compact) "14-day streak · listen today"; StreakSection full "14-day streak · listen today to keep it". Late-night listening that starts before midnight counts for the start day (document in playback.md).

D3. `topBooks: [ReadingStats.BookTotal]` (id, title, author, minutes) sorted minutes desc, then title, then id.uuidString. longestBook* = topBooks.first. Same deterministic tie rule for each day's top book and for bestDay (minutes desc, then earlier date). ReadingDayActivity gains `topBookTitle: String?`. New `todayMinutes: Int`. Stats view shows a "Top books" section with up to 5 rows, hidden when topBooks.count <= 1.

D4. Entry point. New `ReadingStatsScreen` wrapper that owns the ReadingSession/Audiobook queries, the `today` state, and @AppStorage palette + goal, used by both the Favorites zoom destination and a new Settings row "Reading Activity" (`SettingsDestination.readingActivity`, sheet detent switched to .large when pushed). ReadingStatsView gains a `backLabel` parameter ("Library" from Favorites — library.e2e.ts depends on it — "Settings" from Settings). The Settings row is always visible; ReadingStatsView shows a designed empty state when there is no activity (no section may assume bestDay != nil).

D5. Interactive heatmap in ReadingStatsView only (Favorites card heatmap stays non-interactive). Tapping a day selects it; inline summary bar shows formatted date, minutes, top book title; tap same day clears. Hit area larger than the 10–14 pt cell (e.g. column-wide/expanded contentShape), .buttonStyle(.plain), future days ignored, selection ring via existing emphasizeKey. Each day cell is its own accessibility element with date + minutes label and .isSelected trait.

D6. Daily goal: @AppStorage("dailyListeningGoalMinutes") Int, 0 = off, presets 15/30/45/60, set in ReadingStatsView. Device-local. Progress from todayMinutes on its own row in ReadingActivityCard and in ReadingStatsView when > 0. No notifications. Document that progress lags by up to the unflushed chunk (≤5 min).

D7. Palette: @AppStorage("readingHeatmapPalette") String raw value, unknown → amber, picker in ReadingStatsView, applied to card and stats view (replace hardcoded .amber in ContentView). Fix existing bug: mono accent is near-black and invisible in dark mode; make palette accent scheme-aware.

D8. Covers: ReadingStatsScreen/ReadingStatsView fetches only the ≤6 displayed book ids (#Predicate ids.contains) for coverArtData; decode UIImage, scaledToFill + clipped, GeneratedCoverView fallback when nil/unreadable. Never build a map of every book's cover. FreeBooksSection hidden when freeMinutes == 0.

D9. Share card: ShareLink in the custom navBar of ReadingStatsView (the system nav bar is hidden), hidden without activity. A Transferable type renders the PNG lazily (ImageRenderer only on share, never in body), fixed size, scale 3, explicit light colors (no dynamic UIColor), .dynamicTypeSize(.large) pinned: total time, current + longest streak, books finished, last 12 weeks mini heatmap in the chosen palette, "Unpaged" wordmark. No book titles/authors. privacy-policy.md unchanged; support.md gets a short Reading Activity line (+ public Gist mirror, orchestrator does it).

D10. Tests (AGENTS.md testing rules). Unit tests (PagelessTests, written BEFORE the code) only for pure ReadingStats math: 12×5-min chunks → 1 session avg 60; old book-time chunks at 0.5x and 3x still merge; gap > tolerance splits; different books don't merge; midnight-crossing chunks merge; untimed fixture/seeder-style rows fall back to hour grouping; timed/untimed never merge; unsorted input; streak grace yesterday-only; streak breaks after 2 empty days; yesterday-only with daysTracked == 1 (tz shift); future dayKey counts as today; topBooks tie order. E2E for: streak grace copy on the card (fixture with yesterday-only multi-day rows), Settings entry point, heatmap tap → summary, goal persists across relaunch, palette persists across relaunch, share button present. Keep library.e2e.ts passing. No @Model change → SchemaCompatibilityTests unchanged. Android parity (android/.../ReadingActivity.kt) is a follow-up issue, not this PR.

ACCESSIBILITY IDENTIFIERS (contract between UI and E2E layers):
  settings.readingActivity           — Settings row
  readingStats.share                 — share button
  readingStats.palette.<raw>         — palette options (amber|burgundy|mono)
  readingStats.goal.<minutes>        — goal options (0|15|30|45|60)
  readingStats.dayDetail             — selected-day summary bar
  readingStats.heatmap.<YYYY-MM-DD>  — heatmap day cells in ReadingStatsView
  readingStats.emptyState            — empty state
  readingActivity.streak             — streak label on the Favorites card (existing testID "readingActivity" on the card stays)
  readingActivity.goal               — goal progress row on the card
  readingStats.goalProgress          — goal progress in the stats view

## Core layer

Commits: reading stats + tests (6dbb3c2), recorder/seeder/player flush (next). No `@Model` change; `SchemaCompatibilityTests` passes.

- `ReadingStats.compute` (`Models/ReadingStats.swift`): D1 coalescing in `logicalSessionCount`, D2 streak grace with an unbounded walk, D3 `topBooks`/`todayMinutes`/deterministic ties. API: `isStreakActiveToday`, `todayMinutes`, `topBooks: [BookTotal]` (`id, title, author, minutes`, `ranksBefore`), `ReadingDayActivity.topBookTitle`, `empty(today:calendar:)` plus `static var empty`.
- Recorder (D0): `tick(audiobook:uptime:context:)` credits `systemUptime` delta, capped at 3 s, 1 s for the first tick after start/flush. `flush` resets the tick clock. `createdAt` is stamped at flush (chunk end). `AudioPlayerManager.load()` flushes before the first await when the book changes.
- Seeder: `createdAt` = bucket start (`calendar.date(byAdding:)`) + minutes.

Decisions in gaps:
- A day-key later than today makes today "active"; its minutes count in `todayMinutes`. `longestStreak` is `max(scan, currentStreak)` so a future-keyed day can never make it smaller than the current streak.
- Book titles/authors now use the latest snapshot (by `createdAt`, then id) instead of first seen, so recomputes don't depend on input order. Top author ties go to the alphabetically first name.
- `bestDay` ties go to the earlier day; a day's top book uses the same rule as `topBooks`.
- Only the immediately previous row is compared when coalescing, so two books alternating within the same hour never merge; untimed rows of two books in the same hour sort by id.
- Seeded rows are timed, so two seeded rows of one book on one day within ~1 h of each other merge into one logical session.
- `tick`'s unused `secondsElapsed` parameter was replaced by an injectable `uptime` (no other caller).

Verification: `xcodebuild test -only-testing:PagelessTests/ReadingStatsTests -only-testing:PagelessTests/SchemaCompatibilityTests -parallel-testing-enabled NO` on simulator E6A83627 passed (24 + 1 tests), run from a detached worktree of my commits because the shared checkout's UI files did not compile mid-edit. The recorder is untested by design (covered by reading and E2E).

## UI layer

_(pending)_

## E2E & Docs layer

_(pending)_
