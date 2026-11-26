# Slice 01: Reading Stats Accuracy & Habit Loop

## Goal
Fix two trust-breaking math bugs in Reading Stats (streaks resetting every morning and average sessions capped at ~5 min), make Reading Stats discoverable outside the Favorites tab, and add interactive day inspection, an optional daily goal, theme palettes, real book covers, and a shareable summary card.

## Verified Current State
- **Midnight streak reset:** `Pageless/Models/ReadingStats.swift:188-193` counts `currentStreak` starting at `offset = 0` (`today`) and breaks immediately if `activityByDay[todayKey] == nil`. A multi-day listener sees `0` every morning (`ReadingActivityCard.swift:149-153`).
- **5-minute average session cap:** `Pageless/Services/ReadingSessionRecorder.swift:30` flushes a new `ReadingSession` row every 5 minutes, and `Pageless/Models/ReadingStats.swift:202-203` sets `totalSessions = sessions.count` and `avgSession = Double(totalMinutes) / Double(totalSessions)`. A 60-minute sitting creates twelve 5-minute rows, capping average session around 5 min and inflating session count ~12×.
- **Hidden entry point & static heatmap:** `ReadingActivityCard` renders only in `ContentView.swift:776, 804-824` (`tab == .favorites`) and hardcodes `palette: .amber` even though `HeatmapPalette` (`ReadingHeatmap.swift`) defines 3 palettes (`.amber`, `.burgundy`, `.mono`). Heatmap cells are non-interactive.
- **Visual & edge-case polish:** `BestDaySection` and `LongestBookSection` (`ReadingStatsSections.swift`) always draw `GeneratedCoverView` instead of using `Audiobook.coverArtData` when the book still exists in the library. `FreeBooksSection` displays `0% / 0m` even for listeners with zero free-book minutes. There is no shareable stats card or daily listening goal.

## Scope

### 1. Fix Stats Math (Core)
- **Active streak grace for today:** In `ReadingStats.compute`, if `today` has activity, count backwards from `today`; if `today` has no activity yet but `yesterday` does, count backwards from `yesterday` and expose `isStreakActiveToday: Bool` (so UI can show e.g. `"14-day streak · listen today"` instead of `"Start a streak today"`).
- **Logical session coalescing:** Coalesce contiguous `ReadingSession` rows into logical listening sessions when computing `totalSessions` and `avgSession`. Because `ReadingSession` stores `(date, dayKey, hour, minutes, bookID)` without a start timestamp, evaluate the cleanest coalescing rule (e.g., grouping chunks of the same `bookID` within the same or adjacent clock hour when prior hour reached near-continuous play, OR adding an optional `_sessionGroupID: UUID?` backing field on `ReadingSession` populated by `ReadingSessionRecorder` for new sessions with a clean hour-coalescing fallback for historical rows).
- **Per-book breakdown:** Compute a sorted `topBooks` list (not just single `longestBook`) while keeping `ReadingStats` pure and inline-computed.

### 2. Discoverability, Interactivity & Habit Features (UI)
- **Entry point:** Keep `ReadingActivityCard` on Favorites, and add a clean **Reading Activity** row/entry in `SettingsView` (or Library header/toolbar) so Library-first and Shelves-first listeners can reach `ReadingStatsView` anytime.
- **Interactive heatmap:** Tap/select any day cell in `ReadingHeatmapView` (inside `ReadingStatsView`) to display an inline popover/summary bar with the formatted date, minutes listened, and top book for that day.
- **Optional daily listening goal:** Store `@AppStorage("dailyListeningGoalMinutes")` (default `0` = off; presets like `15`, `30`, `45`, `60` min). When enabled, show today's progress toward the daily goal on `ReadingActivityCard` and `ReadingStatsView`.
- **Heatmap palette picker:** Persist `@AppStorage("readingHeatmapPalette")` (`.amber` default) and let users switch between `.amber`, `.burgundy`, and `.mono` inside `ReadingStatsView`.
- **Real cover art & empty free-book guard:** Pass/lookup matching `Audiobook.coverArtData` for `BestDaySection` and `LongestBookSection`, falling back to `GeneratedCoverView`. Hide `FreeBooksSection` when `stats.freeMinutes == 0`.
- **Shareable stats card:** Add a toolbar Share button in `ReadingStatsView` that renders a crisp editorial summary card (total time, current/longest streak, books finished, mini heatmap, Unpaged wordmark) via `ImageRenderer` and presents `ShareLink`.

## Decision Gate (Step 3)
Run Decision Review if adding an optional `_sessionGroupID` backing field to `ReadingSession` (CloudKit synced model) vs. pure heuristic coalescing on existing columns.

## Suggested Layer Split
- **Core:** `Pageless/Models/ReadingStats.swift`, `Pageless/Models/ReadingSession.swift` (if adding optional field), `Pageless/Services/ReadingSessionRecorder.swift`, `PagelessTests/` (pure unit tests for streak-yesterday, coalesced sessions, empty states, `SchemaCompatibilityTests` if model touched).
- **UI:** `Pageless/Views/ReadingStats/*`, `Pageless/Views/ContentView.swift`, `Pageless/Views/SettingsView.swift`.
- **E2E & Docs:** `e2e/tests/` (stats card, interactive heatmap tap, goal persistence, palette switch, share trigger), `docs/ios/playback.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** Deterministic tests covering (a) active streak when listened yesterday but not yet today, (b) streak breaks after 2 missed days, (c) 60-minute listening split into twelve 5-min chunks reports `totalSessions == 1` and `avgSession == 60`, (d) `SchemaCompatibilityTests` if `ReadingSession` schema changes.
- **E2E & Visual (`verify-ebooker`):** Seed reading activity via fixture launch, verify `ReadingActivityCard` + `ReadingStatsView` in light/dark + large Dynamic Type, tap a heatmap cell, set a daily goal, switch palette, relaunch without reset to confirm persistence.
- **Docs:** Update `docs/ios/playback.md` → *Reading sessions and stats*.
