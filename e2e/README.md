# Unpaged mobile end-to-end tests

This directory uses [tester-army/e2e](https://github.com/tester-army/e2e) with its native iOS mobile engine. Packages and the native mobile backend are pinned in `package-lock.json`; they are development tooling only and are not linked into the app. Requires Node >=22.12, Xcode, and an installed simulator runtime.

Tests use deterministic locators and assertions. No AI model, subscription, API key, App Store purchase, or external account is needed; `purchases.e2e.ts` buys only against the local `Products.storekit` configuration. e2e telemetry is disabled in the npm test/list scripts. DEBUG fixture launches use separate local model storage and download manifests, seeded audio/catalog/activity, and no CloudKit sync; see the fixture source and [coverage matrix](COVERAGE.md) for exact scope.

## Run

Create a dedicated simulator once (never select a personal simulator):

```sh
xcrun simctl create 'Unpaged e2e' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0
export E2E_SIMULATOR_UDID='<the returned UDID>'
npm --prefix e2e ci
npm --prefix e2e run build:install
npm --prefix e2e run typecheck
npm --prefix e2e run list
npm --prefix e2e test
```

The build script checks the selected simulator name starts with `Unpaged e2e`, boots it, builds Debug with isolated scratch DerivedData, and installs the app. Set `E2E_BUILD_DIR` to retain/reuse a chosen scratch directory; the printed `build.log` contains diagnostics. The test config refuses to choose a simulator implicitly. It assumes the app is installed; `E2E_APP_PATH` optionally names a build for tests that call `device.installApp()`.

Target launches use `-e2e-fixture`. Each test's reset helper explicitly adds `-e2e-reset-fixture` for its initial launch; subsequent `app.restart()` preserves data, so persistence assertions remain meaningful. One worker and zero retries expose failures without overlapping simulator interaction.

For preference tests, change the value through the UI. A launch argument such as `-appAppearance system` or `-skipBackSeconds 30` overrides the persisted value through UserDefaults' argument domain and prevents a meaningful preference-change assertion.

Wait for an Xcode test process to exit before starting another run on the same simulator. Failure diagnostics can keep it alive after all test cases have finished; its eventual cleanup can shut down the simulator underneath the next run. During diagnosis, `-collect-test-diagnostics never` avoids the optional sysdiagnose collection while retaining the test log and result bundle.

For one flow, from this directory:

```sh
E2E_TELEMETRY_DISABLED=1 npx e2e run tests/native-flows.e2e.ts --grep 'playback'
```

The upstream mobile runner warms its XCTest driver and may open the app without launch arguments during preparation. The dedicated simulator isolates this warm-up from existing user libraries. The driver keeps runtime metadata/cache in `~/.agent-device` unless `AGENT_DEVICE_STATE_DIR` is supplied; these are local test-driver files, not app dependencies.

Reports are generated in `e2e/.e2e/report.json`, `junit.xml`, and `summary.md`; failures retain screenshots. Generated evidence, dependencies, and `.env*` are ignored by Git. Keep useful run evidence outside Git and record actual counts and limitations in the coverage matrix rather than claiming device-only flows passed.

The installed upstream documentation is available offline at `node_modules/e2e/docs/`, especially `mobile.mdx`, `reference/mobile.mdx`, `reference/screen.mdx`, and `reference/expect.mdx`. Diagnose the driver with `npm --prefix e2e run doctor`. In a filesystem sandbox, simulator services and the driver daemon can require a scoped execution approval; a sandbox connection error does not prove a broken simulator.

## Group 2 suites: system UI, StoreKit and a fake catalog

`onboarding`, `player`, `moments`, `cover`, `library`, `free-books` and `purchases` drive surfaces the first suite only reached. They need more than an installed app:

- **`E2E_BUILD_DIR` is required** for `purchases.e2e.ts`. `support/simulator.ts` → `resetStoreKitLedger()` runs the hosted `PagelessTests/StoreKitLedgerReset` test from that build's `.xctestrun`, because storekitd keeps the local StoreKit ledger in memory across launches and an `SKTestSession` is the only supported way to clear it. That `xcodebuild` passes `-parallel-testing-enabled NO`: parallel testing runs on a simulator clone and shuts the e2e simulator down. `resetStoreKitLedger({ failPurchases: true })` arms a simulated network failure through `TEST_RUNNER_E2E_STOREKIT_FAIL`; the next plain reset clears it.
- **Out-of-process sheets are pressed by coordinates.** The StoreKit payment sheet and the PhotosPicker grid belong to system processes and are absent from the app's accessibility tree. Their points (`sheet` in `purchases.e2e.ts`, `pickNewestPhoto` in `cover.e2e.ts`) are for the 402x874 iPhone 18 Pro simulator; another device type needs new points. StoreKit's "You're all set." alert is in the tree but ignores `device.alert('accept')`; tap its OK button.
- **Answer every system alert.** A permission or StoreKit alert left on screen survives relaunches and fails every later test. `onboarding.e2e.ts` resets TCC with `simctl privacy reset` and answers the real prompts; granting a permission with `simctl privacy grant` terminates the app, so "return from Settings" is a cold relaunch.
- **Fake LibriVox feed.** `support/fake-librivox.ts` serves the fixture catalog rows and generated chapter audio on localhost, and can fail chosen chapter requests. `free-books.e2e.ts` points the DEBUG `-e2e-librivox-feed` override at it to qualify a failed download, Try Again, completion and offline playback without the public service.
- `cover.e2e.ts` adds `fixtures/cover.png` (a 600x400 red|blue split) to the simulator's photo library on every run; it is always the newest photo.
- DEBUG-only launch hooks used here: `-e2e-sleep-timer-seconds <n>` (every sleep-timer choice lasts n seconds), `-e2e-online`, `-e2e-librivox-feed <url>`, and the Settings → "Seed Reading Activity · 7/30/113 days" / "Clear Reading Activity" buttons.

```sh
E2E_BUILD_DIR=/private/tmp/unpaged-e2e-build npm --prefix e2e run build:install
E2E_BUILD_DIR=/private/tmp/unpaged-e2e-build npm --prefix e2e test
```

## iOS 18 smoke

Select an installed iOS 18 simulator whose name starts with `Unpaged e2e`, build/install the same Debug app, and run the verified five-case filter:

```sh
export E2E_SIMULATOR_UDID='<dedicated iOS 18 simulator UDID>'
npm --prefix e2e run build:install
npm --prefix e2e test -- --grep 'onboarding Shelves|local playback advances|offline Shelves|Plus purchase|equalizer is reachable'
```

This covers all seven onboarding scenes, local playback/manual moment persistence, offline Shelves, purchase/restore surface reachability, and EQ reachability. See the coverage matrix for the actual run evidence; these checks do not exercise Apple Intelligence on iOS 18.

## Optional live catalog check

After the offline suite completes, opt into public network reads on the same dedicated simulator:

```sh
E2E_LIVE_CATALOG=1 E2E_TELEMETRY_DISABLED=1 npm --prefix e2e test -- tests/live-catalog.e2e.ts
```

This profile adds `-e2e-online` to the fixture launch. The DEBUG fixture suppresses full catalog synchronization; the test exercises the real title search and track request, plays and stops a sample, adds a streaming book locally, verifies its row after relaunch and starts real stream playback. It begins a download, verifies the shared Library cancellation control, cancels immediately, requests it once more and cancels again. It does not download an entire audiobook. Service outages fail this test and should be reported as network coverage limitations. Without opt-in, the live test is explicitly skipped.

A few simulator accessibility references falsely report unobscured Settings controls as covered. `tests/native-actions.ts` uses the framework's documented `tap({ position })` action after a visibility assertion and a fresh native bounding-box read. The point is the current control center, with no hardcoded screen coordinates. Direct native-driver probes verified these controls respond at those bounds. The same helper explicitly focuses the secure ABS field before typing dummy validation input. Ordinary semantic taps remain the default, including onboarding rail navigation.

Secure-field locator typing refocuses an invalid accessibility reference or attempts masked-value confirmation on this simulator. The ABS test advances from Username with the keyboard's Next action and verifies Password focus. `nativeKeyboard.typeFocusedDummyCredential` then types a fixed dummy string through the pinned native client, and `submitFocused` presses Go without refocusing another field. `typeFocusedText` uses the same operation for the moment's fixture character name, followed by a value assertion, avoiding a locator fill retry that can insert text twice. The backend records these actions in its session log; helper errors retain their source location in the E2E failure report. `session.ts` shares the mobile session prefix and enforces one worker; the helper joins slot `0` of that same session. Increasing workers requires replacing that explicit session routing.

EQ tests expand the native sheet before manipulating controls: the clipped medium sheet can overrun XCTest accessibility capture. The helper reads the current native Sheet Grabber bounds and verifies Expanded or native geometry after its action. iOS 18 omits the detent value; its reachability case accepts a half sheet only when both required controls' native bounds are fully visible, followed by the same functional visibility assertions. The enabled toggle targets its inner native switch. If a watchdog has poisoned the dedicated driver, shut down and reboot only that simulator before a new run; do not restart unrelated simulator sessions or the global daemon.
