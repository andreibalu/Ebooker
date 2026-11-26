# Slice 05: Universal Welcome-Back & Frictionless AI Opt-In

## Goal
Give *every* listener a helpful, calm Welcome-Back orientation card when returning to an unfinished book after 3+ days away (not only Apple Intelligence + Plus + downloaded users), layer the on-device AI recap seamlessly on top when eligible, and remove the 3-toggle wall in AI settings.

## Verified Current State
- **6-gate exclusion:** `Pageless/Views/WelcomeBackRecapCard.swift:20-32` and `WelcomeBackRecapViewModel.swift:53-57` render **nothing** unless *all* of iOS 26 + Apple Intelligence + Plus + `useLocalAIFeatures` + `welcomeBackRecaps` + locally downloaded audio + ≥3 days idle + ≥180s progress hold. Free users, older iPhones, and streaming LibriVox/Audiobookshelf listeners get zero re-entry help.
- **3-toggle AI opt-in wall:** `AISettingsView.swift:17-19` defaults `useLocalAIFeatures`, `useSmartMomentNaming`, and `useSmartSummary` all to `false`. Turning on `useLocalAIFeatures` still leaves both Smart Moment Naming and Smart Summary disabled until flipped separately.

## Scope

### 1. Universal Welcome-Back Card
- Show `WelcomeBackRecapCard` on `AudiobookDetailView` for any unfinished, playable book (local *or* streaming) that has been idle `>= 3` days (`WelcomeBackRecapViewModel.returnInterval`), has meaningful progress (`>= 180s`), and has not been dismissed for its current `lastPlayedAt`.
- **Universal content (always instant, zero network/AI needed):**
  - Days since last listened (`"You last listened N days ago"`).
  - Current position context: chapter/track title + percentage / time remaining.
  - Most recent saved moment for the book (if any): label + quoteLine/note preview (1–2 lines) so the listener's own bookmark reminds them of the plot.
  - Actions: **"Rewind 30s & Resume"** (or **"Resume"** honoring `resumeBacktrackSeconds` when already ≥30s, or explicit 30s rewind CTA) and **"Not now"** (device-local dismissal against `lastPlayedAt`, preserving existing behavior).
- **AI enrichment (progressive enhancement):**
  - When the existing AI + Plus + downloaded + `welcomeBackRecaps` gate holds, asynchronously load the on-device narrative recap inside the same card (preserving passive behavior: never prompts for speech permission, silently keeps the universal context if generation declines or fails).
  - Keep all existing accessibility identifiers (`welcomeBack.card`, `welcomeBack.elapsed`, `welcomeBack.headline`, `welcomeBack.text`, `welcomeBack.resume`, `welcomeBack.notNow`, `welcomeBack.providerCalls`) and E2E hooks (`-e2e-fake-recap`, `-e2e-welcome-days`, `-e2e-welcome-threshold-days`) intact.
- Respect a top-level toggle (e.g., Settings → "Welcome-back cards", default on) while keeping `AISettingsKey.welcomeBackRecaps` gating only the AI summary enrichment (or unify cleanly—confirm in Decision Review).

### 2. Remove the 3-Toggle AI Opt-In Wall
- In `AISettingsView.swift`, when the user toggles `useLocalAIFeatures` from `false` → `true` for the first time (when both `useSmartMomentNaming` and `useSmartSummary` are still `false`), automatically enable both `useSmartMomentNaming = true` and `useSmartSummary = true` (users can still turn off individual features afterward).
- Verify no paywall or Plus copy changes violate `docs/ios/purchases.md` or App Review guideline 3.1.1.

## Decision Gate (Step 3)
Run Decision Review on:
1. Settings toggle semantics between universal Welcome-Back cards and AI-powered Welcome-Back recaps (`AISettingsKey.welcomeBackRecaps`).
2. Whether "Rewind 30s & Resume" applies an explicit 30s backtrack or composes with `resumeBacktrackSeconds` (and how it interacts with ABS server reconciliation).

## Suggested Layer Split
- **Core / ViewModel:** `Pageless/ViewModels/WelcomeBackRecapViewModel.swift`, `Pageless/Models/PlaybackSettings.swift`.
- **UI:** `Pageless/Views/WelcomeBackRecapCard.swift`, `Pageless/Views/AudiobookDetailView.swift`, `Pageless/Views/AISettingsView.swift`, `Pageless/Views/SettingsView.swift`.
- **E2E & Docs:** `e2e/tests/welcome-back.e2e.ts` (verify non-AI/free universal card renders with chapter + latest moment + dismisses cleanly; verify existing AI recap tests stay green), `docs/ios/ai.md`, `support.md`.

## Verification Plan
- **E2E & Visual (`verify-ebooker`):**
  - Run `e2e/tests/welcome-back.e2e.ts` (including `-e2e-welcome-days 5` *without* `-e2e-fake-recap` to prove the universal non-AI card renders, shows chapter + moment, and dismisses cleanly; plus existing AI recap tests).
  - Verify `AISettingsView` toggling `useLocalAIFeatures` on auto-enables Smart Naming & Smart Summary and persists across relaunch.
- **Docs:** Update `docs/ios/ai.md` → *Welcome-back recaps* and `support.md`.
