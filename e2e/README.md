# Unpaged mobile end-to-end tests

This directory uses [tester-army/e2e](https://github.com/tester-army/e2e) with its native iOS mobile engine. `package-lock.json` pins the packages and native mobile backend. They are development tools and are not linked into the app. You need Node >=22.12, Xcode, and an installed simulator runtime.

Tests use deterministic locators and assertions. They need no AI model, subscription, API key, App Store purchase, or external account. `purchases.e2e.ts` buys only against the local `Products.storekit` configuration. The npm test/list scripts disable e2e telemetry. DEBUG fixture launches use separate local model storage and download manifests. They seed audio/catalog/activity and use no CloudKit sync. See the fixture source and [coverage matrix](COVERAGE.md) for exact scope.

## Run

Create a dedicated simulator once. Never select a personal simulator:

```sh
xcrun simctl create 'Unpaged e2e' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0
export E2E_SIMULATOR_UDID='<the returned UDID>'
npm --prefix e2e ci
npm --prefix e2e run build:install
npm --prefix e2e run typecheck
npm --prefix e2e run list
npm --prefix e2e test
```

Turn off password AutoFill on the new simulator once. AutoFill shows the Passwords bar above the keyboard. The bar leaves XCTest without keyboard focus, so typing in the Audiobookshelf password field fails. These commands set the device restriction in the simulator's own data folder and reboot only that simulator:

```sh
profiles=~/Library/Developer/CoreSimulator/Devices/$E2E_SIMULATOR_UDID/data/Library/UserConfigurationProfiles
for f in UserSettings.plist EffectiveUserSettings.plist PublicInfo/PublicEffectiveUserSettings.plist; do
  plutil -extract restrictedBool xml1 -o /dev/null "$profiles/$f" 2>/dev/null || plutil -insert restrictedBool -dictionary "$profiles/$f"
  plutil -remove restrictedBool.allowPasswordAutoFill "$profiles/$f" 2>/dev/null
  plutil -insert restrictedBool.allowPasswordAutoFill -xml '<dict><key>value</key><false/></dict>' "$profiles/$f"
done
xcrun simctl shutdown "$E2E_SIMULATOR_UDID"; xcrun simctl boot "$E2E_SIMULATOR_UDID"
```

The build script checks that the selected simulator name starts with `Unpaged e2e`. It boots that simulator, builds Debug with isolated scratch DerivedData, and installs the app. Set `E2E_BUILD_DIR` to retain or reuse a chosen scratch directory. The printed `build.log` contains diagnostics. The test config never chooses a simulator implicitly. It assumes the app is installed. For tests that call `device.installApp()`, `E2E_APP_PATH` optionally names a build.

Launch tests with `-e2e-fixture`. Each test's reset helper adds `-e2e-reset-fixture` to its initial launch. Later `app.restart()` calls preserve data, so persistence assertions remain meaningful. One worker and zero retries expose failures without overlapping simulator interaction.

For preference tests, change the value through the UI. A launch argument such as `-appAppearance system` or `-skipBackSeconds 30` overrides the persisted value in UserDefaults' argument domain. The test then cannot make a meaningful preference-change assertion.

Wait for an Xcode test process to exit before starting another run on the same simulator. Failure diagnostics can keep the process alive after all test cases finish. Its cleanup can then shut down the simulator during the next run. During diagnosis, `-collect-test-diagnostics never` skips the optional sysdiagnose collection but keeps the test log and result bundle.

Run one flow from this directory:

```sh
E2E_TELEMETRY_DISABLED=1 npx e2e run tests/native-flows.e2e.ts --grep 'playback'
```

During preparation, the upstream mobile runner warms its XCTest driver and may open the app without launch arguments. The dedicated simulator keeps this warm-up separate from existing user libraries. Unless you set `AGENT_DEVICE_STATE_DIR`, the driver keeps runtime metadata/cache in `~/.agent-device`. These are local test-driver files, not app dependencies.

Reports go to `e2e/.e2e/report.json`, `junit.xml`, and `summary.md`. Failures retain screenshots. Git ignores generated evidence, dependencies, and `.env*`. Keep useful run evidence outside Git. Record actual counts and limitations in the coverage matrix. Do not claim device-only flows passed.

The installed upstream documentation is available offline at `node_modules/e2e/docs/`. Start with `mobile.mdx`, `reference/mobile.mdx`, `reference/screen.mdx`, and `reference/expect.mdx`. Run `npm --prefix e2e run doctor` to diagnose the driver. In a filesystem sandbox, simulator services and the driver daemon may need a scoped execution approval. A sandbox connection error does not prove that the simulator is broken.

## Suites that need more than an installed app

`onboarding`, `player`, `moments`, `cover`, `library`, `free-books`, `audiobookshelf` and `purchases` use system UI, StoreKit and local fake servers.

- `purchases.e2e.ts` needs `E2E_BUILD_DIR`. `resetStoreKitLedger()` in `support/simulator.ts` runs the hosted `PagelessTests/StoreKitLedgerReset` test from that build's `.xctestrun`. storekitd keeps the local StoreKit ledger in memory across launches. `SKTestSession` is the only supported way to clear it. That `xcodebuild` passes `-parallel-testing-enabled NO` because parallel testing runs on a simulator clone and shuts down the e2e simulator. `resetStoreKitLedger({ failPurchases: true })` arms a simulated network failure through `TEST_RUNNER_E2E_STOREKIT_FAIL`. The next plain reset clears it.
- System processes own the StoreKit payment sheet and PhotosPicker grid, so they do not appear in the app's accessibility tree. Tests press them by coordinates (`sheet` in `purchases.e2e.ts`, `pickNewestPhoto` in `cover.e2e.ts`). The points fit the 402x874 iPhone 18 Pro simulator. Other device types need new points. StoreKit's "You're all set." alert ignores `device.alert('accept')`, so tap its OK button.
- Answer every system alert. Permission, StoreKit, and "Open in Unpaged?" alerts stay on screen after relaunch and fail every later test. Reboot the dedicated simulator to clear them. `onboarding.e2e.ts` resets permissions with `simctl privacy reset` and answers the real prompts. `simctl privacy grant` terminates the app, so returning from Settings starts a cold relaunch.
- `support/fake-librivox.ts` serves the 14 fixture catalog rows and generated chapter audio on localhost. It supports `Range` requests for streaming. `startFakeLibriVox({ trackSeconds, audioDelayMs })` sets the chapter length and holds each audio response. `failAudio` and `failSearch` inject HTML 500 errors. `free-books.e2e.ts` points the DEBUG `-e2e-librivox-feed` override at this server.
- `support/fake-audiobookshelf.ts` serves an Audiobookshelf server at 127.0.0.1:47378. It has two book libraries, one podcast library, three books, and 30-second WAV tracks. It accepts the fixed login `e2e-reader` / `e2e-password` and API key `e2e-api-key`. It records every request, every progress PATCH, and the token on each audio request. Loopback is a private host, so plain http raises no warning.
- `player.e2e.ts` copies `PagelessTests/Fixtures/chaptered.m4b` into the app's fixture folder after a reset launch. It then imports the file with `-e2e-import-file chaptered.m4b`.
- `cover.e2e.ts` adds `fixtures/cover.png` (a 600x400 red and blue split) to the simulator's photo library on every run. It is always the newest photo.
- `support/simulator.ts` also opens URLs on the simulator (`openURL`) and writes the app's defaults from outside (`writeAppBool`). This stands in for the Play Latest Book App Intent.

DEBUG-only launch hooks:

| Hook | Effect |
| --- | --- |
| `-e2e-fixture` | Opens the separate fixture store and seeds it once. |
| `-e2e-reset-fixture` | Deletes the fixture store, saved scene state, the fixture Audiobookshelf login and onboarding preference keys before seeding. |
| `-e2e-online` | Lets NetworkMonitor report a connection. The fixture is offline otherwise. |
| `-e2e-librivox-feed <url>` | Sends LibriVox feed requests to `<url>`. |
| `-e2e-sleep-timer-seconds <n>` | Makes every sleep-timer choice last n seconds. |
| `-e2e-import` | Makes the import button hand a file to the import pipeline instead of opening the Files picker. |
| `-e2e-import-file <name>` | Picks `<name>` from the fixture folder for `-e2e-import`. Without it, the app generates a 123-second WAV. |

Fixture mode Settings also shows "Seed Reading Activity · 7/30/113 days" and "Clear Reading Activity".

```sh
E2E_BUILD_DIR=/private/tmp/unpaged-e2e-build npm --prefix e2e run build:install
E2E_BUILD_DIR=/private/tmp/unpaged-e2e-build npm --prefix e2e test
```

## iOS 18 smoke

Select an installed iOS 18 simulator whose name starts with `Unpaged e2e`. Build/install the same Debug app and run the verified five-case filter:

```sh
export E2E_SIMULATOR_UDID='<dedicated iOS 18 simulator UDID>'
npm --prefix e2e run build:install
npm --prefix e2e test -- --grep 'onboarding Shelves|local playback advances|offline Shelves|Plus purchase|equalizer is reachable'
```

This covers all seven onboarding scenes, local playback/manual moment persistence, offline Shelves, purchase/restore surface reachability, and EQ reachability. See the coverage matrix for actual run evidence. These checks do not exercise Apple Intelligence on iOS 18.

## Optional live catalog check

After the offline suite completes, opt into public network reads on the same dedicated simulator:

```sh
E2E_LIVE_CATALOG=1 E2E_TELEMETRY_DISABLED=1 npm --prefix e2e test -- tests/live-catalog.e2e.ts
```

This profile adds `-e2e-online` to the fixture launch. The DEBUG fixture skips full catalog synchronization. The test uses the real title search and track request. It plays and stops a sample, adds a streaming book locally, verifies its row after relaunch, and starts real stream playback. It begins a download and checks the shared Library cancellation control. It cancels immediately, requests the download once more, and cancels again. It does not download an entire audiobook. Service outages fail this test. Report them as network coverage limitations. Without opt-in, the live test is explicitly skipped.

A few simulator accessibility references incorrectly report visible Settings controls as covered. After a visibility assertion and a fresh native bounding-box read, `tests/native-actions.ts` uses the framework's documented `tap({ position })` action. The tap point is the control's current center, with no hardcoded screen coordinates. Direct native-driver probes confirmed that controls respond at those bounds. Semantic taps remain the default, including for onboarding rail navigation. The mini player covers the bottom of the last library row. The locator long-press rejects a covered center, so `longPressVisibleTop` presses near the card's top edge through the native client. Navigation Back buttons use the previous screen's title as their label. Tests find them with `getByTestId('BackButton')`. After a slow accessibility query the driver can fall back to a snapshot that lists some nodes twice, so `toBeHidden` checks on text and single-control taps in alerts use `.first()` or `.last()`.

On this simulator, secure-field locator typing refocuses an invalid accessibility reference or attempts masked-value confirmation. The ABS test moves from Username with the keyboard's Next action, then types without a focus assertion because XCTest does not report focus on that secure field. `nativeKeyboard.typeFocusedDummyCredential` types a fixed dummy string through the pinned native client. `submitFocused` presses Go without refocusing another field. `typeFocusedText` uses the same operation for the moment's fixture character name, then checks its value. This avoids a locator fill retry that can insert text twice. The backend records these actions in its session log. Helper errors retain their source location in the E2E failure report. `session.ts` shares the mobile session prefix and enforces one worker. The helper joins slot `0` of that same session. To increase workers, replace that explicit session routing.

EQ tests expand the native sheet before manipulating controls because the clipped medium sheet can overrun XCTest accessibility capture. After its action, the helper reads the current native Sheet Grabber bounds and verifies Expanded or native geometry. iOS 18 omits the detent value. Its reachability case accepts a half sheet only when both required controls' native bounds are fully visible. It then runs the same functional visibility assertions. The enabled toggle targets its inner native switch. If a watchdog has poisoned the dedicated driver, shut down and reboot only that simulator before a new run. Do not restart unrelated simulator sessions or the global daemon.
