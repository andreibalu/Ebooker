# Slice 06: Equalizer Volume Boost Fix, Spoken-Word DSP & Global Defaults

## Goal
Fix the silent Volume Boost bug in `EqualizerSheet` / `EqualizerTap`, upgrade the existing real-time `MTAudioProcessingTap` with spoken-word clarity tools (Mono Downmix and Dynamic Loudness Leveling), persist slider drags cleanly on release, and let listeners set global default Speed and EQ for new books (or apply to all books).

## Verified Current State
- **Volume Boost bug:** `Pageless/Views/EqualizerSheet.swift:72-114` leaves `amplifierCard` ("Volume Boost", `0...+12 dB`) enabled and full opacity when `equalizer.isEnabled == false` (unlike `presetsCard` and `bandsCard`), yet `Pageless/Services/EqualizerTap.swift:252` bypasses the entire render callback (`guard enabled else { return }`). Moving Volume Boost with EQ off produces zero audible change.
- **Excessive SwiftData writes during drag:** `AudioEqualizerService.setPreamp` / `setBandGain` (`AudioEqualizerService.swift:68-89`) persist to SwiftData on every slider drag tick instead of once on drag end (unlike `PlaybackSpeedSheet` + `setPlaybackRate(_:persist:)`).
- **Per-book-only audio settings:** `Audiobook.playbackRate` (`Audiobook.swift:23`) and `Audiobook.equalizerConfiguration` (`Audiobook.swift:178-206`) have no global default for newly imported/added books and no "Apply to all books" action.
- **Untapped DSP headroom:** `EqualizerTap` already runs a lock-safe Float32 `MTAudioProcessingTap` with 5 peaking biquads + soft limiter, but lacks Mono Downmix (for single-AirPod listening on stereo recordings) and Dynamic Loudness Leveling (for uneven quiet/loud narrations).

## Scope

### 1. Fix Volume Boost Activation & Drag-End Persistence
- Decouple tap activation from EQ-bands-only toggle: in `EqualizerTap` / `EqualizerConfiguration`, run the tap whenever *any* DSP feature is active (`isEnabled` EQ bands, `preampDB > 0`, `monoDownmix`, or `loudnessLeveling`), applying EQ biquads only when `isEnabled` is true and Volume Boost / Mono / Leveling independently whenever active.
- Add `persist: Bool = true` to `AudioEqualizerService.setPreamp` and `setBandGain` (matching `AudioPlayerManager.setPlaybackRate`), updating live DSP coefficients immediately while dragging and writing SwiftData once on `Slider(onEditingChanged: { if !$0 { equalizer.persist() } })`.

### 2. Spoken-Word DSP in `EqualizerTap`
- **Mono Downmix (`monoDownmix: Bool`):** In the Float32 render callback (when `channelCount >= 2`), average left/right samples `(L + R) * 0.5` across channels before/after EQ without allocating on the realtime audio thread.
- **Dynamic Loudness Leveling (`loudnessLeveling: Bool`):** Add a lightweight, allocation-free RMS/envelope follower + gentle soft-knee compressor + makeup gain inside `EqualizerTap`'s pre-allocated `TapState` (before the existing soft limiter) so quiet whispers rise and loud bursts stay comfortable.
- Keep `EqualizerConfiguration` backward-compatible JSON (decoding missing `monoDownmix` / `loudnessLeveling` keys as `false`, zero CloudKit schema change since `equalizerConfiguration` is already a JSON backing field!).
- Expose clean toggles for **Mono Audio** and **Loudness Leveling** in `EqualizerSheet` alongside Volume Boost and EQ bands.

### 3. Global Audio Defaults (Speed & EQ)
- Add `@AppStorage("defaultPlaybackRate")` (default `1.0`) and `@AppStorage("defaultEqualizerConfigurationJSON")` (default flat/off).
- Seed new `Audiobook` rows (local import, LibriVox add/download, Audiobookshelf add/download) with these defaults.
- Add compact **"Set as Default"** and **"Apply to All Books"** (with confirmation alert) actions in `PlaybackSpeedSheet` and `EqualizerSheet` (and show Default Speed in `SettingsView`).

## Decision Gate (Step 3)
Run Decision Review on:
1. Realtime audio-thread safety of `EqualizerTap` changes (zero heap allocations, `os_unfair_lock` copy-only pattern, compressor attack/release/ratio constants, and behavior on non-interleaved vs interleaved buffers).
2. Exact UX of Volume Boost vs EQ toggle in `EqualizerSheet` (independent card vs auto-enable).

## Suggested Layer Split
- **Core / DSP:** `Pageless/Models/EqualizerSettings.swift`, `Pageless/Services/EqualizerTap.swift`, `Pageless/Services/AudioEqualizerService.swift`, `Pageless/Services/LibraryImportService.swift`, `Pageless/Services/StreamingLibraryService.swift`, `Pageless/Services/AudiobookshelfLibraryService.swift`, `PagelessTests/` (DSP buffer unit tests + JSON backward-compat decoding tests).
- **UI:** `Pageless/Views/EqualizerSheet.swift`, `Pageless/Views/PlaybackSpeedSheet.swift`, `Pageless/Views/SettingsView.swift`.
- **E2E & Docs:** `e2e/tests/` (EQ sheet Volume Boost + Mono + Leveling toggles persist across relaunch; Set as Default applies to newly imported book), `docs/ios/playback.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** Pure DSP tests feeding synthetic Float32 buffers through the processing math verifying: (a) Volume Boost applies gain when EQ bands are disabled, (b) Mono Downmix averages L/R identically, (c) Loudness Leveling boosts quiet signals and tames peaks without clipping past `±1.0`, (d) legacy `EqualizerConfiguration` JSON decodes cleanly with new booleans defaulting to `false`.
- **E2E & Visual (`verify-ebooker`):** Verify `EqualizerSheet` (remembering `e2e/README.md` sheet-expansion guidance!) and `PlaybackSpeedSheet` at standard & large text; confirm defaults persist and seed a new imported book.
- **Docs:** Update `docs/ios/playback.md` → *Equalizer* & *Playback speed* and `support.md`.
