# Unpaged flow coverage

The native suite drives the real SwiftUI app on the dedicated `Unpaged e2e` simulator with the tester-army/e2e mobile engine. A DEBUG launch with `-e2e-fixture` opens a separate SwiftData store seeded with two books of generated PCM audio, two moments, one reading session and 14 LibriVox catalog rows. Relaunch steps omit `-e2e-reset-fixture`, so a value that survives the relaunch was saved to disk.

This matrix covers every iOS feature except Apple Intelligence and iCloud sync, which have their own qualification. Three local fakes replace outside services:

- `support/fake-librivox.ts` serves the LibriVox feed and chapter audio on localhost.
- `support/fake-audiobookshelf.ts` serves an Audiobookshelf server on localhost.
- The local `Products.storekit` configuration stands in for the App Store.

## Latest validation, 2026-10-07

Unit suite on the iPhone 18 Pro simulator (iOS 27.0), 623 Swift Testing tests in 73 suites. One StoreKit test, `legacyAIUnlockStillGrantsPlusPermanently`, failed once and passed when `StoreKitTransactionTests` was rerun on its own (14 of 14). The XCTest UI groups ran 4 and 8 tests with no failures.

Native suite on the dedicated `Unpaged e2e` simulator (iOS 27.0), 68 tests in 11 files, with `live-catalog.e2e.ts` skipped because it is opt-in. The last full run (`01a11309-db66-7f6f-bb7e-c26929b3043b`) passed 65 of 67. Both failures were test faults, which are now fixed and passed on rerun (`01a1131d-9ac0-799f-b181-a26a9211e8f3`):

- The Today's Pick helper counted one day short between midnight and 1 a.m. while daylight saving time is in effect.
- The coffee row's subtitle is part of the button's label and is not always listed as separate text.

Earlier full runs that day found and fixed these test faults:

- A Plus trial left over from a purchase test run on its own. `purchases.e2e.ts` now clears the StoreKit ledger after each test as well.
- Password AutoFill on the simulator blocked typing into the Audiobookshelf password field. The README now has the setup step that turns it off.
- Locators that matched a node twice while a removed card animated out.

The suite also found three app bugs, fixed in the same change:

- Deleting the book loaded in the player left the mini player and Now Playing showing the deleted book.
- Deleting a downloaded book while it was still preparing to play did not cancel the load. A Codex review found this one, and a unit test covers it.
- The downloads link, `unpaged://library/downloads`, opened Library underneath a pushed detail screen instead of showing the download.

## Flow matrix

The second column lists what the native suite asserts. The third lists the Swift test suites for the same code and what neither layer proves.

| Flow | Native assertions | Swift coverage and remaining boundary |
| --- | --- | --- |
| Onboarding | Own-books and Shelves choices, all seven scenes through the progress rail, persisted routing and completion. Real microphone and speech prompts: allowing both auto-advances and Done shows "Allowed". A denied prompt opens the Settings app, a grant there shows on return, and Done shows "Mic only". The resume slider, skip chips and moment-offset stepper change the Done summary and the Settings pickers after relaunch (`onboarding.e2e.ts`, `native-flows.e2e.ts`, `extended-flows.e2e.ts`) | OnboardingManagerTests. The Apple Intelligence and iCloud scenes are informational only. |
| Empty library | Removing both books shows "Your Library Is Empty" with Import Audiobook, Favorites shows "No Favorites Yet", and Browse Shelves opens Shelves (`library.e2e.ts`) | None needed beyond the view. |
| Favorites | Remove and add a favorite, each checked after relaunch (`native-flows.e2e.ts`) | AudiobookTests |
| Rename | The context-menu rename survives relaunch and keeps chapter titles. A renamed single-track book shows the new title in the player and mini player and hides the file's chapter title (`native-flows.e2e.ts`, `player.e2e.ts`) | LibraryViewModelTests, AudioTrackTests. Lock screen and CarPlay text need a device. |
| Cover photo | A photo from the system PhotosPicker opens the crop screen. Cancel keeps the generated cover. Use Photo replaces it and survives relaunch, and Remove cover restores the generated cover (`cover.e2e.ts`) | The crop rectangle is not measured. |
| Library sort | Duration and Title reorder two books and survive relaunch. Library and Favorites keep separate sorts (`extended-flows.e2e.ts`, `library.e2e.ts`) | LibraryViewModelTests |
| Own-book deletion | Cancel keeps the book. "Remove from App" keeps the audio folder in the app container and "Also Delete Files" removes it (`native-flows.e2e.ts`, `library.e2e.ts`) | LibraryImportMutationTests. The subscriber "Remove from this iPhone" path needs iCloud. |
| Deleting the playing book | Removing the loaded book, whether an Audiobookshelf stream or a downloaded free book, also clears the mini player (`audiobookshelf.e2e.ts`, `free-books.e2e.ts`) | AudioPlayerManagerSkipTests checks `unloadIfCurrent` for the loaded book, another book, a stream still loading and a downloaded book still preparing. |
| Import | The DEBUG `-e2e-import` hook hands a generated WAV to the real import pipeline. The metadata review, the import, relaunch and playback all run for real (`extended-flows.e2e.ts`) | LibraryImportFingerprintTests, LibraryImportMutationTests. The system Files picker itself is not driven. |
| Playback | Real AVPlayer play and pause, next and previous chapter, scrubber drag with the VoiceOver value, and the mini player toggling playback and reopening the player (`native-flows.e2e.ts`, `player.e2e.ts`) | AudioPlayerManagerLoadTests, AudiobookSavedProgressResumeTests. Interruptions, background audio and AirPlay routes need a device. |
| Skip intervals and resume offset | Settings set Skip Forward to 45 s, Skip Backward to 15 s and On Resume to 15 s earlier. The player's skip buttons move by those amounts, and after relaunch the library menu's Resume starts 15 s before the saved position (`player.e2e.ts`) | AudioPlayerManagerSkipTests, PlaybackPersistenceTests |
| Chapters | The chapter list marks the current chapter and jumps to another. An imported single-file M4B lists its embedded chapters "Opening", "The Middle" and "Ending", and choosing one updates the chapter line (`player.e2e.ts`) | EmbeddedChapterReaderTests, PlaybackChapterTests |
| Speed and sleep timer | A chosen speed is remembered for the book after relaunch. A sleep timer, shortened to 4 s by `-e2e-sleep-timer-seconds`, pauses playback and resets its label (`player.e2e.ts`, `native-flows.e2e.ts`) | PlayerQuickActionDisplayTests, PlaybackPersistenceTests |
| Equalizer | The player opens the Equalizer. Enabling it and choosing Voice Boost survive relaunch, and Reset to Flat selects Flat (`extended-flows.e2e.ts`, `native-flows.e2e.ts`) | AudioEqualizerServiceTests. The DSP output is not measured. |
| Mark progress | A marker on chapter 2 survives relaunch and saved-progress playback returns to chapter 2 (`extended-flows.e2e.ts`) | PlaybackPersistenceTests |
| Moments | A manual moment saves and survives relaunch. Name, note, quote, mood and cast edits persist. Pinning moves a moment to the top. Context-menu delete and swipe delete persist (`native-flows.e2e.ts`, `moments.e2e.ts`) | MomentTests, PlayerViewModelCommitTests, AudiobookDetailViewModelTests. AI-filled values are out of scope. |
| Moment filters | Category, character and mood filters each narrow to the right moments, and Clear All restores them (`extended-flows.e2e.ts`, `moments.e2e.ts`) | AudiobookDetailViewModelFilterTests |
| Reading activity | A saved session opens the stats view. Seeded 7, 30 and 113-day histories switch between "Last 7 days", "Last 30 days" and "Last 4 months" (`native-flows.e2e.ts`, `library.e2e.ts`) | ReadingStats aggregation tests |
| Settings | Home tab, Appearance in all six combinations with the system appearance, Reset Onboarding, Privacy Policy and Terms of Use opening Safari (`extended-flows.e2e.ts`, `library.e2e.ts`) | PlaybackSettings enums. Page contents of the external documents are not checked. |
| Plus purchase and restore | Through the real local StoreKit payment sheet: a trial unlocks Plus and survives relaunch, closing the sheet leaves Plus locked, a simulated network failure reports an error, and restore with or without sign-in reports no error. The header Plus hub reaches the AI and iCloud settings without a purchase, as Apple guideline 3.1.1 requires (`purchases.e2e.ts`) | PlusEntitlementStoreTests, StoreKitTransactionTests. Ask to Buy, renewals and a sandbox account need TestFlight. |
| Coffee tip | Cancel shows "Purchase cancelled.", and a purchase shows the thank-you and unlocks nothing (`purchases.e2e.ts`) | CoffeeTipStoreTests |
| Shelves browsing | From the fixture cache: Today's Pick, the Love & Society collection, Other Recordings with Version 2 pointing back at the Original, and the language, genre and length filters (`free-books.e2e.ts`). Offline Shelves keeps cached books (`native-flows.e2e.ts`) | BrowseLibriVoxViewModelTests, LibriVoxCollectionViewModelTests, LibriVoxAlternativesFinderTests. The 20k-book sync is off in fixture mode. |
| Shelves search results | A search with no match shows "Nothing on this shelf." A feed outage shows "Couldn't search LibriVox." (`free-books.e2e.ts`) | LibriVoxSearchAndSyncTests. "Couldn't Load Shelves" needs an empty catalog cache, which the fixture never has, so only BrowseLibriVoxViewModelTests cover it. |
| Sample | Against 60-second fake chapters, the sample fetches the first track, Stop Sample stops it, and a second sample stops by itself after 20 s (`free-books.e2e.ts`) | SamplePlayerTests |
| Add a free book as a stream | Add to Library fetches no audio. View in Library plays the book from the fake feed, and "Remove from Library" removes it for good (`free-books.e2e.ts`) | LibriVoxBookDetailViewModelTests, FreeBookIdentityServiceTests |
| Download a free book | A chapter fails with an HTML 500, Try Again finishes the download, the book plays from disk with the feed stopped, and "Remove Download" removes it (`free-books.e2e.ts`) | LibriVoxDownloadManagerTests, LibriVoxBackgroundDownloadCoordinatorTests. Delivery while the app is suspended needs a device. |
| Downloads link and cancel | With a download in progress on the book's detail screen, `unpaged://library/downloads` (the Live Activity's link) pops to Library with the download in view. Cancel download removes it, and nothing remains after relaunch (`free-books.e2e.ts`) | UnpagedRouteTests, DownloadLiveActivityControllerTests. The Live Activity itself needs a device. |
| Audiobookshelf sign-in and browsing | Username and password sign-in shows the shelf, Continue Listening at 40%, search, a no-match message and a library switch. Podcast libraries never appear. The login and chosen library survive relaunch with one `/login` request (`audiobookshelf.e2e.ts`) | AudiobookshelfClientTests, AudiobookshelfLibraryTests |
| Audiobookshelf playback | A server book is added and streams with the session token on every audio request. Pausing sends a progress PATCH with the 60 s duration. The detail then offers Resume. "Remove from Library" removes it from Unpaged and sends no DELETE to the server (`audiobookshelf.e2e.ts`) | AudiobookshelfClientTests. A real server and Tailscale need a configured account. |
| Audiobookshelf errors and settings | An API key connects and Settings shows the server. Disconnect forgets it after relaunch. A wrong password errors on the password field. Plain http to a public host warns before sending credentials. An unreachable server shows Retry, which recovers. A malformed address fails locally (`audiobookshelf.e2e.ts`, `extended-flows.e2e.ts`) | AudiobookshelfClientTests |
| Siri shortcut | The Play Latest Book flag, written to the app's defaults while it is in the background, starts the most recently played book when the app comes forward (`library.e2e.ts`) | SiriIntentTests. Siri voice invocation needs a device. |
| Live catalog | Opt-in with `E2E_LIVE_CATALOG=1`. Searches the public feed, plays a sample, adds a stream, and requests and cancels a download (`live-catalog.e2e.ts`) | Network outages fail this case. |

## Not covered by the native suite

- Apple Intelligence smart save and recap, and iCloud sync, the restore match and Cloud Library. These are excluded from this pass.
- CarPlay, Control Center, lock screen metadata and background audio. These need a physical device.
- The system Files picker. The import hook replaces only the picker.
- Real App Store and Audiobookshelf accounts.

## Isolation and safety

- Use only the dedicated `Unpaged e2e` simulator. The config refuses any other.
- `-e2e-reset-fixture` deletes only `Application Support/E2EFixtures`, the saved scene state, the fixture's own Audiobookshelf Keychain item and the preference keys onboarding writes.
- In fixture mode the app keeps its Audiobookshelf login under a separate Keychain service, so tests never touch a real login.
- `purchases.e2e.ts` buys only against `Products.storekit` and clears the local StoreKit ledger before and after each test.
- `onboarding.e2e.ts` resets and grants microphone and speech permissions for the app on the dedicated simulator only.
- The fake servers listen on 127.0.0.1 and close after each test.
