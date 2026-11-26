# Slice 04: Sleep Timer Comfort

## Goal
Turn Unpaged's sleep timer into a genuinely comforting bedtime tool: smooth audio fade-out instead of an abrupt cut, quick extend (`+5/+15m`) and optional shake-to-extend, custom duration selection, remember-last-timer convenience, and a gentle auto-rewind on expiry so listeners wake up right where they drifted off.

## Verified Current State
- `SleepTimerOption` (`Pageless/Models/PlaybackSettings.swift:92-115`) offers only `5`, `15`, `30`, `60` minutes and `End of chapter` (`-1`).
- Minute timer expiry (`Pageless/Services/AudioPlayerManager.swift:774-781`) calls `self.pause()` abruptly with zero fade-out.
- End-of-chapter sleep (`AudioPlayerManager.swift:794-813`) hard-stops via `AVPlayerItem.forwardPlaybackEndTime`.
- No custom minute duration, no `+5/+15 min` quick extend, no shake-to-extend, no remembered last duration, and no auto-rewind on sleep expiry.

## Scope

### 1. Smooth Audio Fade-Out on Expiry
- Begin a smooth 12-second volume fade-out before minute-timer expiry (and before chapter-end when remaining playback time reaches the fade window; shorter timers fade over `min(12s, duration * 0.25)`).
- Ramp smoothly to `0.0` (e.g., `AVPlayer.volume` step ramp or gain multiplier in `EqualizerTap` — confirm in Decision Review that it works reliably in background audio and with AirPlay/Bluetooth without altering system volume).
- Immediately restore volume to `1.0` when the user cancels the timer, extends the timer, or presses Play again.

### 2. Gentle Auto-Rewind on Sleep Expiry
- When a sleep timer expires naturally (not manual pause/cancel), nudge the saved playback position back by a small configurable amount (e.g., `@AppStorage("sleepTimerRewindSeconds")`, default `30s`, toggleable or options `Off / 15s / 30s / 60s`) so the listener picks up right before they fell asleep. Respect chapter-end boundaries cleanly (optional: apply only on minute timers, or rewind before the chapter end—decide in Step 3).

### 3. Quick Extend, Custom Duration & Remember Last Timer
- Replace the simple menu with a compact `SleepTimerSheet` (matching `PlaybackSpeedSheet`'s tactile calm aesthetic):
  - Existing presets (`5m`, `15m`, `30m`, `60m`, `End of chapter`) + **"Custom…"** stepper/slider (`1–180 min`).
  - While a minute timer is active, show prominent **`+5 min`**, **`+15 min`**, and **Cancel** buttons.
  - Persist `@AppStorage("lastSleepTimerSeconds")` so tapping a subtle "Last used" quick chip (or long-pressing the timer button) arms your favorite bedtime timer in one tap.

### 4. Optional Shake-to-Extend
- Add an opt-in (or default-on) `@AppStorage("sleepTimerShakeToExtend")` toggle in `SleepTimerSheet` / Settings.
- While a sleep timer is running (or during its fade-out window / within 30s after expiry), detecting a deliberate shake via `CoreMotion` (`CMMotionManager` accelerometer threshold, active *only* while the sleep timer is armed so battery impact is zero otherwise) extends the timer by the last chosen increment (default `+10 min`), restores volume if fading, and plays a subtle haptic/soft confirmation.
- Cleanly stop `CMMotionManager` updates whenever the timer cancels, expires past the grace window, or the app terminates.

## Decision Gate (Step 3)
Run Decision Review on:
1. Fade-out mechanism (`AVPlayer.volume` vs `EqualizerTap` gain) in background audio + streaming + AirPlay.
2. Whether auto-rewind on expiry applies to End-of-Chapter or minute timers only.
3. Shake-to-extend background behavior limitations on iOS (be explicit in UI copy/docs about screen-on vs background accelerometer limits).

## Suggested Layer Split
- **Core:** `Pageless/Services/AudioPlayerManager.swift` (fade ramp, extend, expiry rewind, custom duration), `Pageless/Services/SleepTimerShakeDetector.swift` (new, protocol-backed for testability), `Pageless/Models/PlaybackSettings.swift`.
- **UI:** `Pageless/Views/SleepTimerSheet.swift` (new), `Pageless/Views/PlayerView.swift`, `Pageless/Views/PlayerQuickActionDisplay.swift`, `Pageless/Views/SettingsView.swift`.
- **E2E & Docs:** `e2e/tests/player.e2e.ts` (keeping existing `-e2e-sleep-timer-seconds` hook working! Add custom duration, `+5m` extend, cancel, expiry rewind assertions), `docs/ios/playback.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** Fade curve / duration clamping math, extend calculation, expiry rewind clamping & cross-track behavior.
- **E2E & Visual (`verify-ebooker`):** Verify existing chapter-sleep and minute-sleep E2E tests stay green (`-e2e-sleep-timer-seconds`), add E2E coverage for `SleepTimerSheet` custom duration + `+5m` extend + cancel; note physical-iPhone-only limitation for background fade-out and real accelerometer shake.
- **Docs:** Update `docs/ios/playback.md` → *Sleep timer* and `support.md`.
