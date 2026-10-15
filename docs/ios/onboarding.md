# Onboarding

Read this before changing the welcome flow, its scenes, the preferences it sets, or the home-tab choice. Code lives in `Views/Onboarding/` (`OnboardingFlowView.swift`, `OnboardingScenes.swift`, `OnboardingTheme.swift`) and `Services/OnboardingManager.swift`.

The flow runs once on first launch and again after Settings → "Reset Onboarding". It replaced an older spotlight walkthrough; the flow is the whole onboarding.

## Gate and presentation

- `OnboardingManager` is only a completion gate: `isComplete` (stored as `onboardingComplete`), `complete()`, `reset()`. Its init counts the legacy `onboardingPhase == 3` as complete.
- `ContentView` shows `OnboardingFlowView` in an `.overlay` behind an `if !onboarding.isComplete` read in `body`. That keeps the dependency tracked and puts the flow on the first frame of a cold launch with no library flash; a `fullScreenCover` binding can miss the change.

## Flow

- One paged vertical `ScrollView` (`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`) holds the full-screen scenes, in the order of `sceneLabels`, with a progress-dot rail on the right edge.
- The active scene index drives every reveal, count-up and stagger: paged rows instantiate before they center, so a bare `.onAppear` fires early. Gate animation starts on `isActive`, as the existing scenes do.
- Preference controls bind live to the same `@AppStorage` keys Settings uses (`resumeBacktrackSeconds`, `skipBackSeconds`, `skipForwardSeconds`, `momentBacktrackSeconds`), so persistence is automatic and the final summary reads the same source.
- **Home tab.** "Open Library" calls `finish()`, which completes the gate and opens the chosen tab. Choosing Shelves stores `startOnFreeBooks = true`: from then on every launch opens on Shelves (a one-time `.onAppear` guard in `ContentView`) and `LibraryTab.order` becomes Favorites / Shelves / Library, which drives both the tab picker and the swipeable pages. "My books" and legacy users get `false` and Favorites / Library / Shelves. The internal `.allBooks` / `.freeBooks` symbols and stored keys keep their old names.
- Re-tapping the selected choice card clears it, and the user can scroll on with no choice. `finish()` then opens Shelves for this session but stores `false`, so the next launch uses Library order.

## Permissions scene

This scene is the app's only up-front permission request (see `AGENTS.md` → Platform gates).

- `OBPermissionsScene` has two cards: Microphone (`AVAudioApplication.requestRecordPermission`) and Speech Recognition (`SFSpeechRecognizer.requestAuthorization`). A card animates to "Allowed" only when the system grants.
- Tapping a denied or restricted card opens the app's Settings page; there is no other error UI.
- Cards seed from live authorization status and re-seed when `scenePhase` returns to `.active`, catching grants made in Settings.
- The scene is skippable and never blocks scrolling. When both grants come from this scene's buttons, it auto-advances after a short delay if the user is still on it.
- The Done summary's "Voice access" row reads the same state.

## Informational scenes

The Apple Intelligence and iCloud scenes explain features only. Purchase and sync state stay out of them: no paywall, no toggles.

## Visual rules

The flow must look the same on every device and iOS version:

- fixed point sizes and a fixed-width centered content column;
- `.dynamicTypeSize(.large)` clamped on the flow's root (the rest of the app follows Dynamic Type);
- the app's own Appearance setting, applied at the window;
- every animation honours Reduce Motion.

Tokens (`OB` colors, `OBMotion`), type primitives (`OBEyebrow`, `OBHeadline`, `OBSub`, `obSerif`) and the `obReveal` / `obParallax` modifiers live in `OnboardingTheme.swift`. Scene widgets (choice and permission cards, `OBResumeSlider`, chip rows, stepper, `OBHeatmap`, the moment-naming card, `OBSyncGraphic`, the summary) live in `OnboardingScenes.swift`.
