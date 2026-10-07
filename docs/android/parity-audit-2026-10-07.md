# Android parity audit, 2026-10-07

Reference: the 45 Swift files under this worktree's `Pageless/Views/`, their
models/services, and `visual-evidence/ios-reference-1.4.1/`. This audit concerns
the shipping app. Debug seed controls are listed separately. "Same" means the
corresponding product control/state exists. It does not mean pixel identity,
identical platform sheet geometry, SF Symbols, Apple fonts, or physical-device
qualification. The slice verification document records which states ran.

Payments remain excluded. Slice 7 owns car/voice/shortcut work; slice 8 owns sync,
cloud library, restore, backup and deletion semantics; slice 9 owns AI, recaps and
AI onboarding. These rows identify ownership, not completed Android behavior.

## Screen and interaction review

| iOS surface | Android surface | Status |
| --- | --- | --- |
| ContentView: My Library, count, Settings, import, three tabs and pager | LibraryScreen, LibraryHeader | same |
| ContentView: Plus header and Plus sheet | No purchase control | intentionally excluded |
| ContentView: independent Favorites/Library sort menus, Recently Played / Title / Author / Duration / Date Added | UnpagedPreferences, sortedBooks | same |
| ContentView: Shelves Catalog source, LibriVox / Audiobookshelf, unconfigured Connect your server | CatalogSourceMenu, ABSConnect | same |
| ContentView: Resume context action | LibraryBookCard → PlayerController | fixed in this slice |
| ContentView: Favorite / Unfavorite context action | LibraryBookCard → LibraryViewModel | fixed in this slice |
| ContentView: Rename own/ABS book, Book title, Save / Cancel, persisted title | Rename Audiobook dialog, SQLiteLibraryStore.rename | fixed in this slice |
| ContentView: Delete / Remove Download / Remove from Library context labels | LibraryBookCard | fixed in this slice |
| ContentView: deletion confirmation, Remove from App / Also Delete Files and subscription-aware copy | Existing LibraryScreen dialog; slice 8 reconciles retained audio and sync | owned by another slice |
| ContentView: import/read/index/favorite/rename alerts | LibraryScreen operation-specific titles, typed failures and retry | fixed in this slice |
| ContentView: No Favorites Yet; heart hint | EmptyFavorites | same |
| ContentView: Your Library Is Empty; Files / free classics actions | EmptyLibrary | same |
| ContentView: pinned Downloads section | SharedDownloads in Library and Shelves | fixed in this slice |
| AudiobookCardView: cover, heart tint, Played / Playing badge, author, duration, storage, progress | LibraryBookCard | same |
| AudiobookCardView: user-selected and embedded artwork | LibraryBookCover / AndroidAudioMetadataReader | fixed in this slice |
| AudiobookCardView: backup badge | Slice 8 | owned by another slice |
| AudiobookDetailView: header, timestamp, storage, Play / Continue, progress summary | BookDetails | same |
| AudiobookDetailView: Finished replaces percent/remaining copy | BookDetails | fixed in this slice |
| AudiobookDetailView: Player toolbar only for the loaded book | DetailTopBar | fixed in this slice |
| AudiobookDetailView: streaming LibriVox Download for Offline and status | BookDetails → ShelvesSession | fixed in this slice |
| AudiobookDetailView: Change cover, photo selection, Remove cover | EditableBookCover, private cover.png | fixed in this slice |
| AudiobookDetailView: empty-moments bookmark hint, even when collapsed | MomentList | fixed in this slice |
| AudiobookDetailView: moments count, disclosure, pin-first order, filters/no matches/Clear Filters | MomentList, MomentFilters | same |
| AudiobookDetailView: ordered tracks disclosure and duration/play rows | BookDetails, PlaybackRules | same |
| AudiobookDetailView: Other Recordings from local catalog identity | AlternativesSection in library detail | fixed in this slice |
| AudiobookDetailView: Your Progress/recap/short summary/loading/error | Slice 9 | owned by another slice |
| AudiobookDetailView: cloud match, restore and subscription-aware actions | Slice 8 | owned by another slice |
| AudiobookTrackRow: numbered track/title/duration/play | BookDetails track rows | same |
| CoverCropView: Crop Cover, Cancel / Use Photo, square preview, pinch/drag, clamping, upright 600px output | CoverCrop | fixed in this slice |
| GeneratedCoverView: deterministic palette, serif title, glyph/rule/UNPAGED proportions | GeneratedBookCover / CoverPalette | same |
| ImportAudiobookSheet: Details, Title, Author, Files, Total length, Imported Files, Save / Cancel | ImportReview | same |
| ImportAudiobookSheet: embedded artwork preview | ImportReview and staged cover.png | fixed in this slice |
| ImportAudiobookSheet: cloud-match hint | Slice 8 | owned by another slice |
| PlayerView: cover, file/title/author, buffering, scrubber, elapsed/remaining | FullPlayer | same |
| PlayerView: cover uses the selected/imported artwork | FullPlayer / MiniPlayer / media metadata | fixed in this slice |
| PlayerView: previous/next chapters, skip intervals, play/pause | PlayerController, PlaybackRules | same |
| PlayerView: 0.8 / 1 / 1.25 / 1.5 / 1.75 / 2 speed choices | FullPlayer | same |
| PlayerView: Sleep Timer, Off / 5 / 15 / 30 / 60 minutes, remaining timer | FullPlayer, PlaybackPersistenceRules | same |
| PlayerView: Mark Progress Here, confirmation text, Mark Progress / Cancel | FullPlayer | same |
| PlayerView: Save Moment manual metadata sheet | MomentEditSheet | same |
| PlayerView: smart naming/warnings/Analyzing state | Slice 9 | owned by another slice |
| PlayerView: system audio-output selection | OutputRouteButton, Android output switcher | same |
| PlayerQuickActionDisplay: compact rate title and sleep clock | speedLabel, trackDuration | same |
| ChapterListSheet: Chapters / Done, current highlight/waveform, number/title/duration, current scroll position | ChaptersSheet | same |
| ChapterListSheet: number minimum width 24 and open-sheet persistence through appearance changes | ChaptersSheet | fixed in this slice |
| ChapterListSheet: Nero chpl and QuickTime chapter tracks, including und | Mp4Chapters + existing chapter pipeline | fixed in this slice |
| MiniPlayerBar: title/chapter, buffering, pause/play, open full player | MiniPlayer | same |
| MomentRow: tapping row edits; play button starts from timestamp | MomentList | fixed in this slice |
| MomentRow: pin/unpin, notes, time, delete context action and reveal/full swipe | MomentList, SwipeMoment | same |
| MomentEditSheet: Name/Note/Quote/Categories/Mood/Characters, tag removal, Done/Cancel, blank-name guard | MomentEditSheet | same |
| MomentEditSheet: AI generated label/warnings and AI quote placeholder | Slice 9 | owned by another slice |
| MomentFilterSheet: Categories/Characters/Moods, multiple selections, Clear All/Done | MomentFilterSheet | same |
| EqualizerSheet: enable, Volume Boost 0–12dB, high-boost warning, preset chips, five manual bands, Reset to Flat | EqualizerSheet / EqualizerDsp | same |
| SettingsView: Sources, Audiobookshelf Server status | SettingsScreen | fixed in this slice |
| SettingsView: Playback / Listening preferences.; Open To; all four preference captions and trays | SettingsScreen | same |
| SettingsView: App / Appearance & tour.; System / Light / Dark | SettingsScreen / UnpagedTheme | same |
| SettingsView: Appearance then Reset Onboarding row, Show the welcome walkthrough again | SettingsScreen | fixed in this slice |
| SettingsView: Reset Onboarding?, explanation, Reset / Cancel | SettingsScreen confirmation | fixed in this slice |
| SettingsView: About / The fine print.; Privacy Policy / Terms of Use | SettingsScreen, system browser | same |
| SettingsView: external-link symbol | LegalRow | fixed in this slice |
| SettingsView: Plus and Support/coffee sections | No empty purchase section | intentionally excluded |
| SettingsView: AI and cloud settings rows | Slices 9 and 8 | owned by another slice |
| SettingsDesign: header/type sizes, captions, rounded cards, hairlines, section spacing, Done pill | SettingsScreen and UnpagedTheme | same |
| AppAppearance: persistent System/Light/Dark, system observation | UnpagedPreferences / UnpagedTheme | same |
| OnboardingFlowView: seven pages, rail navigation, reduced motion, saved completion, preference bindings | OnboardingScreen | same |
| OnboardingScenes: welcome Shelves/My books, home choice, playback preferences, sample year, final Open Library | OnboardingScreen | same |
| OnboardingScenes: microphone/speech/voice permissions | Slice 7 | owned by another slice |
| OnboardingScenes: AI moments/recap interactive scene | Slice 9 | owned by another slice |
| OnboardingScenes: sync/library scene and final sync summary | Slice 8 | owned by another slice |
| OnboardingTheme: warm colors, headings, cards, rail and reveal | OnboardingScreen theme helpers | same |
| ReadingActivityCard: adaptive heatmap, activity total/window, streak, Less/More, open report | ActivityCard / Heatmap | same |
| ReadingStatsView: Reading title on scroll, Library/back/footer navigation | ReadingStatsScreen | same |
| ReadingStatsSections: hero, date window, total time and session/day plurals | ReadingStatsScreen | fixed in this slice |
| ReadingStatsSections: A long weekday with author, duration display and best-day miniature heatmap | ReadingStatsScreen best-day section | fixed in this slice |
| ReadingStatsSections: time-of-day wording and peak clock center/spoke width | ClockChart and reading report | fixed in this slice |
| ReadingStatsSections: longest book, streak/current/longest, 28-day bar, metric cards | ReadingStatsScreen | same |
| ReadingStatsSections: mostly with author copy, free share, closing quote | ReadingStatsScreen | fixed in this slice |
| ReadingHeatmap: adaptive 7/30/120-day grid, date labels, palette and Less/More | Heatmap | same |
| ReadingStatsSections/ReadingHeatmap: dark amber accent | ActivityAmber theme getter | fixed in this slice |
| BrowseLibriVoxView: search, clear, language/genre/length, menus, selected underline | ShelvesScreen / ShelvesViewModel | same |
| BrowseLibriVoxView: All Languages / All Genres / Any Length menu labels | FilterMenu | fixed in this slice |
| BrowseLibriVoxView: preparation/search, saved books/matches, partial results, retries and empty/error states | StatusLine / ShelvesEmpty | same |
| BrowseLibriVoxView: deterministic daily hero, collapsible Collections, chart excluding hero, footer | Hero, Collections, CatalogRow | same |
| LibriVoxBookRow: cover/title/author/duration and independent 20-second sample | CatalogRow / ShelvesSession.sample | same |
| LibriVoxBookDetailView: title/author/duration/size/language, sample, About/show more/less | CatalogDetail | same |
| LibriVoxBookDetailView: Download Free Book, Add to Library, Adding…, Added to Your Library / View in Library | CatalogDetail / CatalogLibraryService | same |
| LibriVoxBookDetailView: shared progress/cancel/retry/completion and failed-entry Dismiss | ShelvesSession / WorkManager | fixed in this slice |
| LibriVoxCollectionView: local-first ordered books, offline partial state, Retry | ShelvesScreen collection | same |
| LibriVoxCollectionView: dedicated courtesy footer | CollectionColophon | fixed in this slice |
| LibriVoxAlternativesSection: count, explanation, original/version badge, duration, cover, sample, detail navigation | Shared AlternativesSection | fixed in this slice |
| LibriVoxDownloadSection: navigation-independent jobs, Library/Shelves shared status | SharedDownloads / ShelvesSession | fixed in this slice |
| LibriVoxDownloadSection: durable partial bytes, force-stop/relaunch resume, backoff, foreground notification/cancel | LibriVoxDownloadWorker / ResumableFile | fixed in this slice |
| ABSConnectView: server/username/password or API key, explanation, connect/cancel, insecure-host confirmation | ABSConnect, Android encrypted credentials | same |
| ABSBrowseView: library picker/search, Continue Listening, Recently Added, All Books, offline/expired/unreachable/error/empty/retry | ABSBrowse | same |
| ABSBookDetailView: artwork/narrator/duration/progress, add/play, About this book, streaming explanation | ABSBookDetail | same |
| ABSComponents: editorial source labels, serif text/cover fallback and progress | ABSScreens helpers | same |
| ABSServerSettingsView: connected account, Open in Shelves, disconnect confirmation, unconfigured Connect a Server | ABSServerSettings | same |
| CloudLibraryView: saved/streaming buckets, locate/adopt/delete | Slice 8 | owned by another slice |
| RestoreMatchSheet: restore progress/moments/settings or Add as new | Slice 8 | owned by another slice |
| MatchCloudEntrySheet: search/match/overwrite confirmations | Slice 8 | owned by another slice |
| ICloudBackupBadge: card and inline badge | Slice 8 | owned by another slice |
| ICloudSettingsView: cloud configuration and ownership copy | Slice 8 | owned by another slice |
| AISettingsView: capability, local processing, smart-save/recap switches | Slice 9 | owned by another slice |
| PlusHubView: plans, purchases, trial, membership management | No Android equivalent | intentionally excluded |
| UnpagedPlusCard: products/trial/restore/manage actions | No Android equivalent | intentionally excluded |
| BuyMeACoffeeView: consumable purchase/status/price | No Android equivalent | intentionally excluded |

## Evidence limits

The audit identifies functional counterparts, source-derived copy/layout fixes and
parallel ownership. It is not a claim that every network failure, locale, codec,
animation or system-picker state has been exercised. Android uses Material icons,
Roboto/system serif, Android permission/output/photo-provider UI and Compose
sheets. A screenshot match cannot establish background reliability or handset
battery/thermal behavior. The supplied dark-detail capture duplicates Library;
it is not a valid dark-detail reference.

The iOS DEBUG-only reading seed controls are development tools. Android has the
debug ReadingActivitySeeder/ReadingFixtureActivity counterpart, isolated from
release builds. They do not represent a shipping app feature.

## Literal-copy inventory

The following inventory keeps each concrete display/accessibility literal tied
to its Swift line and Android owner. Dynamic values, model-generated titles,
conditional copy and interaction rules are covered in the preceding table.
Apple storage/device nouns map to Android equivalents in ABS/permissions. This
inventory is a source checklist, not proof that every conditional state ran.
The shipping-product rows above take precedence over repeated generic literals
such as "Cancel" in shared/purchase components.

| iOS surface | Android surface | Status |
| --- | --- | --- |
| `AISettingsView.swift:50` AI Features | Slice 9 | owned by another slice |
| `AISettingsView.swift:72` AI generation and transcription stay on this iPhone. Features require Apple Intelligence and a compatible device. | Slice 9 | owned by another slice |
| `AISettingsView.swift:103` Thoughtful moments, picked up where you left off. | Slice 9 | owned by another slice |
| `AISettingsView.swift:106` Apple Intelligence can suggest names, quotes, characters and moods for saved moments, and recap the passage around your last listening point. Processing runs on-device. | Slice 9 | owned by another slice |
| `AISettingsView.swift:110` These features require an Apple Intelligence–compatible device with Apple Intelligence available. | Slice 9 | owned by another slice |
| `AISettingsView.swift:139` Use local AI features | Slice 9 | owned by another slice |
| `AISettingsView.swift:148` Smart moment naming | Slice 9 | owned by another slice |
| `AISettingsView.swift:149` Suggest names for saved moments based on the audio | Slice 9 | owned by another slice |
| `AISettingsView.swift:155` Smart summary | Slice 9 | owned by another slice |
| `AISettingsView.swift:156` Summarize where you left off on the book detail screen | Slice 9 | owned by another slice |
| `AISettingsView.swift:163` Short progress headline | Slice 9 | owned by another slice |
| `AISettingsView.swift:164` Replace \u{201C}Your progress\u{201D} with a 3\u{2013}4 word summary | Slice 9 | owned by another slice |
| `AISettingsView.swift:172` Unpaged Plus includes these features. | Purchases excluded | intentionally excluded |
| `AISettingsView.swift:186` Apple Intelligence features are part of Unpaged Plus. | Purchases excluded | intentionally excluded |
| `AISettingsView.swift:189` View Unpaged Plus | Purchases excluded | intentionally excluded |
| `AudiobookCardView.swift:30` Connecting | LibraryBookCard / LibraryBookCover | same |
| `AudiobookCardView.swift:38` Playing | LibraryBookCard / LibraryBookCover | same |
| `AudiobookCardView.swift:116` · | LibraryBookCard / LibraryBookCover | same |
| `AudiobookCardView.swift:132` · | LibraryBookCard / LibraryBookCover | same |
| `AudiobookCardView.swift:135` \(mb) MB | LibraryBookCard / LibraryBookCover | same |
| `AudiobookCardView.swift:162` OK | LibraryBookCard / LibraryBookCover | same |
| `AudiobookDetailView.swift:138` Player | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:150` Match with iCloud backup | Slice 8 | owned by another slice |
| `AudiobookDetailView.swift:160` Match with iCloud backup | Slice 8 | owned by another slice |
| `AudiobookDetailView.swift:174` Import Everything | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:177` Cancel | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:179` Your current progress and moments for ‘\(audiobook.title)’ will be replaced by your iCloud backup. | Slice 8 | owned by another slice |
| `AudiobookDetailView.swift:224` Download for Offline | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:227` Save this LibriVox book to listen without internet. | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:241` Download for Offline | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:281` \(mb) MB | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:351` Tap the bookmark in the player to save a moment | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:359` No moments match your filters | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:362` Clear Filters | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:517` Play saved progress | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:530` Where Was I? | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:570` Filter | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:579` Filter moments | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:698` Change cover | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookDetailView.swift:719` Remove cover | BookDetails / MomentList / AlternativesSection | same |
| `AudiobookTrackRow.swift:34` \(trackPosition + 1) | BookDetails track rows | same |
| `BuyMeACoffeeView.swift:19` Buy me a coffee | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:62` Enjoying Unpaged? | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:68` An optional one-time tip to support Unpaged. It does not unlock features, add content, or provide any other benefit. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:80` One-time support | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:87` In-app purchases are unavailable on this device. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:103` Try again | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:123` Thank you for the coffee. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:128` Purchase cancelled. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:130` Purchase is pending approval. We will show thanks after Apple confirms it. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:133` Coffee support is unavailable right now. Try again later. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:136` The purchase could not be completed. Please try again. | Purchases excluded | intentionally excluded |
| `BuyMeACoffeeView.swift:148` The price shown above comes from the App Store and is localized for your region. You can send a coffee again whenever you like. Tips cannot be restored. | Purchases excluded | intentionally excluded |
| `ChapterListSheet.swift:28` Chapters | ChaptersSheet | same |
| `ChapterListSheet.swift:32` Done | ChaptersSheet | same |
| `ChapterListSheet.swift:46` \(chapter.index + 1) | ChaptersSheet | same |
| `ChapterListSheet.swift:72` Chapter \(chapter.index + 1), \(chapter.title) | ChaptersSheet | same |
| `CloudLibraryView.swift:136` Turn on iCloud sync in Settings to back up your library and see it across devices. | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:148` Delete | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:169` Delete | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:187` Your iCloud Library is empty. Books you import will be backed up here automatically. | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:194` iCloud Library | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:214` Adopt These Files | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:217` Choose Different Files | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:221` The selected files do not have the same tracks as ‘\(restoreFlow.pending?.book.title ??  | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:231` Delete Permanently | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:234` Cancel | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:236` Permanently removes ‘\(deleteCandidate?.title ??  | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:242` OK | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:265` Saved | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:287` Streaming | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:290` Backed up | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:313` Locate… | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:338` Stream | Slice 8 | owned by another slice |
| `CloudLibraryView.swift:345` Open in Shelves | Slice 8 | owned by another slice |
| `ContentView.swift:240` Remove from Library | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:248` Remove from Library | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:256` Remove Download | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:264` Remove from this iPhone | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:269` Remove from App | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:273` Also Delete Files | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:278` Cancel | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:283` Removes this book from Unpaged. It stays on your Audiobookshelf server, and you can add it again from Shelves. | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:286` Removes this book from your library on this iPhone. Your progress and bookmarks stay in your iCloud Library, and you can stream it again anytime. | Slice 8 | owned by another slice |
| `ContentView.swift:288` This will remove the book from your library. You can add it again from Shelves. | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:292` Removes the download from this iPhone. Your progress and bookmarks stay in your iCloud Library, and you can stream or re-download it anytime. | Slice 8 | owned by another slice |
| `ContentView.swift:294` This will remove the downloaded audiobook. You can download it again from Shelves. | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:297` Removes the audio from this iPhone. The book stays in your iCloud Library, and you can restore it anytime. | Slice 8 | owned by another slice |
| `ContentView.swift:299` Choose whether to remove this audiobook from Unpaged only, or also delete its imported audio files from local storage. | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:306` Book title | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:307` Save | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:314` Could Not Rename Audiobook | LibraryScreen / LibraryBookCard | fixed in this slice |
| `ContentView.swift:317` Cancel | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:322` OK | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:400` \(visibleLibraryBookCount) | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:406` My Library | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:423` Unpaged Plus | Purchases excluded | intentionally excluded |
| `ContentView.swift:507` Favorites | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:543` \(source.name) | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:544` Connect your server | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:734` Resume | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:752` Could Not Save Favorite | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:757` Rename | LibraryScreen / LibraryBookCard | fixed in this slice |
| `ContentView.swift:951` No Favorites Yet | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:953` Tap the heart on any book to save it here. | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:957` Your Library Is Empty | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:959` Import an audiobook from Files, or browse thousands of free public-domain classics. | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:961` Import Audiobook | LibraryScreen / LibraryBookCard | same |
| `ContentView.swift:967` Browse Shelves | LibraryScreen / LibraryBookCard | same |
| `CoverCropView.swift:41` Pinch to zoom  ·  Drag to reposition | CoverCrop | fixed in this slice |
| `CoverCropView.swift:48` Crop Cover | CoverCrop | fixed in this slice |
| `CoverCropView.swift:53` Cancel | CoverCrop | fixed in this slice |
| `CoverCropView.swift:56` Use Photo | CoverCrop | fixed in this slice |
| `EqualizerSheet.swift:27` Equalizer | EqualizerSheet | same |
| `EqualizerSheet.swift:33` Done | EqualizerSheet | same |
| `EqualizerSheet.swift:46` Equalizer | EqualizerSheet | same |
| `EqualizerSheet.swift:48` Adjust tone and boost quiet books | EqualizerSheet | same |
| `EqualizerSheet.swift:76` Volume Boost | EqualizerSheet | same |
| `EqualizerSheet.swift:78` Override the max volume for quiet books | EqualizerSheet | same |
| `EqualizerSheet.swift:83` +\(Int(equalizer.preampDB)) dB | EqualizerSheet | same |
| `EqualizerSheet.swift:99` High boost may distort very quiet passages. | EqualizerSheet | same |
| `EqualizerSheet.swift:120` Preset | EqualizerSheet | same |
| `EqualizerSheet.swift:171` Manual EQ | EqualizerSheet | same |
| `EqualizerSheet.swift:223` Hz | EqualizerSheet | same |
| `EqualizerSheet.swift:242` Reset to Flat | EqualizerSheet | same |
| `FreeBooks/BrowseLibriVoxView.swift:150` Search titles & authors… | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:185` All Languages | ShelvesScreen / ShelvesViewModel | fixed in this slice |
| `FreeBooks/BrowseLibriVoxView.swift:207` All Genres | ShelvesScreen / ShelvesViewModel | fixed in this slice |
| `FreeBooks/BrowseLibriVoxView.swift:229` Any Length | ShelvesScreen / ShelvesViewModel | fixed in this slice |
| `FreeBooks/BrowseLibriVoxView.swift:283` Searching LibriVox… | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:345` Offline — showing saved matches. | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:360` Offline — showing saved books. | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:410` RETRY | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:524` by \(book.authorDisplay) | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:559` Collections | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:606` \(collection.bookIDs.count) books | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:716` No Internet Connection | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:718` Shelves needs a connection the first time to load audiobooks from LibriVox. Connect to Wi‑Fi or cellular and tap Retry. | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:720` Retry | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:729` Couldn’t Load Shelves | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:733` Try Again | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:742` Search LibriVox | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:744` Search by title or author, or use the filters above to browse by language, genre, or length. | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/BrowseLibriVoxView.swift:756` Every book here is read by [LibriVox](https://librivox.org) volunteers and free in the public domain — yours to keep, forever. | ShelvesScreen / ShelvesViewModel | same |
| `FreeBooks/LibriVoxAlternativesSection.swift:40` Other Recordings | AlternativesSection | fixed in this slice |
| `FreeBooks/LibriVoxAlternativesSection.swift:42` \(alternatives.count) | AlternativesSection | fixed in this slice |
| `FreeBooks/LibriVoxAlternativesSection.swift:46` Same book, different narrators. Play a sample to compare. | AlternativesSection | fixed in this slice |
| `FreeBooks/LibriVoxBookDetailView.swift:99` \(book.estimatedDownloadSizeMB) MB | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:126` About | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:226` Download Free Book | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:257` Add to Library | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:267` Adding to library… | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:281` Try Again | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:304` Added to Your Library | CatalogDetail | same |
| `FreeBooks/LibriVoxBookDetailView.swift:310` View in Library | CatalogDetail | same |
| `FreeBooks/LibriVoxCollectionView.swift:56` Free books courtesy of [LibriVox](https://librivox.org) \u{2014} public domain audio recorded by volunteers. | ShelvesScreen collection | same |
| `FreeBooks/LibriVoxCollectionView.swift:79` Retry | ShelvesScreen collection | same |
| `FreeBooks/LibriVoxDownloadSection.swift:120` Downloads · \(entries.count) | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:210` Cancel download | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:213` Retry | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:214` Dismiss | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:248` Preparing download… | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:253` Finishing download… | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:257` Downloading… | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:269` Cancelling… | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:275` Try Again | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:276` Dismiss | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:281` Downloaded | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `FreeBooks/LibriVoxDownloadSection.swift:290` Cancel | SharedDownloads / LibriVoxDownloadWorker | fixed in this slice |
| `GeneratedCoverView.swift:57` UNPAGED | GeneratedBookCover / CoverPalette | same |
| `GeneratedCoverView.swift:70` Cover for \(title) | GeneratedBookCover / CoverPalette | same |
| `GeneratedCoverView.swift:158` Pride and Prejudice | GeneratedBookCover / CoverPalette | same |
| `GeneratedCoverView.swift:160` Moby-Dick | GeneratedBookCover / CoverPalette | same |
| `GeneratedCoverView.swift:162` The Adventures of Sherlock Holmes | GeneratedBookCover / CoverPalette | same |
| `ICloudBackupBadge.swift:32` Backed up to iCloud | Slice 8 | owned by another slice |
| `ICloudBackupBadge.swift:50` Backed up to iCloud | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:25` iCloud Sync | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:43` iCloud Sync uses your private iCloud account. Audio files remain on each device. Subscription plans and billing are shown in Unpaged Plus settings. | Purchases excluded | intentionally excluded |
| `ICloudSettingsView.swift:64` OK | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:73` Keep titles, progress, moments, recaps and listening history in sync across your devices through your private iCloud account. Audio files stay on each device. | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:88` iCloud Sync is included with Unpaged Plus. | Purchases excluded | intentionally excluded |
| `ICloudSettingsView.swift:124` Included with Unpaged Plus | Purchases excluded | intentionally excluded |
| `ICloudSettingsView.swift:126` Turn on sync below when you're ready | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:143` Unpaged Plus includes iCloud Sync across your devices. | Purchases excluded | intentionally excluded |
| `ICloudSettingsView.swift:146` View Unpaged Plus | Purchases excluded | intentionally excluded |
| `ICloudSettingsView.swift:167` Sync library with iCloud | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:180` iCloud Library | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:181` See and manage everything backed up to iCloud | Slice 8 | owned by another slice |
| `ICloudSettingsView.swift:199` Manage Subscription | Purchases excluded | intentionally excluded |
| `ICloudSettingsView.swift:200` Manage or cancel through your Apple ID | Slice 8 | owned by another slice |
| `ImportAudiobookSheet.swift:47` Title | ImportReview | same |
| `ImportAudiobookSheet.swift:50` Author | ImportReview | same |
| `ImportAudiobookSheet.swift:60` Already listened to this before? After adding, open the book and tap the **iCloud** button (top right) to match it with your backup and restore your old progress and moments. | Slice 8 | owned by another slice |
| `ImportAudiobookSheet.swift:91` Import Audiobook | ImportReview | same |
| `ImportAudiobookSheet.swift:95` Cancel | ImportReview | same |
| `ImportAudiobookSheet.swift:108` OK | ImportReview | same |
| `MatchCloudEntrySheet.swift:60` Importing replaces this book’s current progress, moments, and EQ with the iCloud backup’s. | Slice 8 | owned by another slice |
| `MatchCloudEntrySheet.swift:65` Match with iCloud | Slice 8 | owned by another slice |
| `MatchCloudEntrySheet.swift:70` Cancel | Slice 8 | owned by another slice |
| `MatchCloudEntrySheet.swift:81` Import Everything | Slice 8 | owned by another slice |
| `MatchCloudEntrySheet.swift:84` Cancel | Slice 8 | owned by another slice |
| `MatchCloudEntrySheet.swift:86` Your current progress and moments for ‘\(localBook.title)’ will be replaced by the iCloud backup. | Slice 8 | owned by another slice |
| `MatchCloudEntrySheet.swift:92` OK | Slice 8 | owned by another slice |
| `MiniPlayerBar.swift:57` Connecting to stream… | MiniPlayer | same |
| `MomentEditSheet.swift:77` Moment name | MomentEditSheet | same |
| `MomentEditSheet.swift:91` Note | MomentEditSheet | same |
| `MomentEditSheet.swift:94` AI generated | Slice 9 | owned by another slice |
| `MomentEditSheet.swift:110` Done | MomentEditSheet | same |
| `MomentEditSheet.swift:115` Cancel | MomentEditSheet | same |
| `MomentEditSheet.swift:192` Clear mood | MomentEditSheet | same |
| `MomentEditSheet.swift:229` Add character | MomentEditSheet | same |
| `MomentEditSheet.swift:283` Remove \(text) | MomentEditSheet | same |
| `MomentEditSheet.swift:358` Edit Moment | MomentEditSheet | same |
| `MomentFilterSheet.swift:94` Clear All | MomentFilterSheet | same |
| `MomentFilterSheet.swift:100` Filter Moments | MomentFilterSheet | same |
| `MomentFilterSheet.swift:104` Done | MomentFilterSheet | same |
| `MomentRow.swift:85` Delete | MomentList / SwipeMoment | same |
| `MomentRow.swift:90` Edit Moment | MomentList / SwipeMoment | same |
| `MomentRow.swift:127` Delete | MomentList / SwipeMoment | same |
| `MomentRow.swift:139` Delete moment | MomentList / SwipeMoment | same |
| `MomentRow.swift:203` Play from this moment | MomentList / SwipeMoment | same |
| `Onboarding/OnboardingScenes.swift:130` Unpaged | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:146` Shelves | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:149` My books | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:298` Microphone | Slice 7 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:303` Speech Recognition | Slice 7 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:500` On resume | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:501` Rewind a little when you press play after a break. | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:506` Skip buttons | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:507` How far the back and forward buttons jump. | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:517` Save moment offset | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:518` Where a saved moment lands relative to now. | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:630` Rewind on resume | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:735` \(label) \(option.title) | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:753` minus | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:764` plus | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:806` A sample year | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:831` across  | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:832` 240 sessions | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:833`  and  | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:834` 168 days | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:835` . | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:962` Pick up where you left off | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:966` You left off as Bingley settles at Netherfield and Mrs. Bennet plans the Meryton ball. | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:985` Runs on your device. Nothing leaves your phone. | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:1009` P | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:1015` SAVED MOMENT · 1:24:07 | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:1019` Untitled moment | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:1024` First impression of Mr. Darcy | Slice 9 | owned by another slice |
| `Onboarding/OnboardingScenes.swift:1239` Starting with  | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:1241` . Adjust anything in Settings whenever you like. | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:1252` Open Library | OnboardingScreen | same |
| `Onboarding/OnboardingScenes.swift:1265` Takes you straight to your books. | OnboardingScreen | same |
| `PlayerView.swift:74` Name this Moment | FullPlayer / PlayerController | same |
| `PlayerView.swift:140` Chapters | FullPlayer / PlayerController | same |
| `PlayerView.swift:148` Close player | FullPlayer / PlayerController | same |
| `PlayerView.swift:209` Connecting to stream… | FullPlayer / PlayerController | same |
| `PlayerView.swift:229` File \(player.currentTrackIndex + 1) | FullPlayer / PlayerController | same |
| `PlayerView.swift:256` Chapter: \(title) | FullPlayer / PlayerController | same |
| `PlayerView.swift:288` - | FullPlayer / PlayerController | same |
| `PlayerView.swift:306` Previous chapter | FullPlayer / PlayerController | same |
| `PlayerView.swift:315` Skip backward | FullPlayer / PlayerController | same |
| `PlayerView.swift:350` Skip forward | FullPlayer / PlayerController | same |
| `PlayerView.swift:362` Next chapter | FullPlayer / PlayerController | same |
| `PlayerView.swift:391` Mark Progress | FullPlayer / PlayerController | same |
| `PlayerView.swift:394` Cancel | FullPlayer / PlayerController | same |
| `PlayerView.swift:397` This will update your progress marker to the current playback position. | FullPlayer / PlayerController | same |
| `PlayerView.swift:431` \(rate.formatted(.number.precision(.fractionLength(0...2))))× | FullPlayer / PlayerController | same |
| `PlayerView.swift:433` \(rate.formatted(.number.precision(.fractionLength(0...2))))× | FullPlayer / PlayerController | same |
| `PlayerView.swift:467` Off | FullPlayer / PlayerController | same |
| `PlayerView.swift:509` Analyzing… | Slice 9 | owned by another slice |
| `PlayerView.swift:729` Playback position | FullPlayer / PlayerController | same |
| `PlusHubView.swift:68` Membership | Purchases excluded | intentionally excluded |
| `PlusHubView.swift:76` Membership | Purchases excluded | intentionally excluded |
| `PlusHubView.swift:110` Your backed-up library. | Purchases excluded | intentionally excluded |
| `PlusHubView.swift:126` iCloud Library | Purchases excluded | intentionally excluded |
| `PlusHubView.swift:127` See and manage everything backed up to iCloud | Purchases excluded | intentionally excluded |
| `PlusHubView.swift:174` OK | Purchases excluded | intentionally excluded |
| `ReadingStats/ReadingActivityCard.swift:75` ACTIVITY | ActivityCard / Heatmap | same |
| `ReadingStats/ReadingActivityCard.swift:83` · \(subtitle) | ActivityCard / Heatmap | same |
| `ReadingStats/ReadingHeatmap.swift:474` Less | Heatmap | same |
| `ReadingStats/ReadingHeatmap.swift:484` More | Heatmap | same |
| `ReadingStats/ReadingStatsSections.swift:272` listening across \(Text( | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:272` \(stats.activityByDay.count) \(stats.activityByDay.count == 1 ?  | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:326` with \(lastName). | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:435` Peak hour: \(Text(fmtClock12(stats.bestHour)).fontWeight(.semibold).foregroundColor(.primary)) | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:520` peak | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:593` by \(author) | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:605` hours | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:652` day streak | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:660` longest | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:670` 4 weeks ago | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:672` today | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:737` Steady, generous sessions — \(Text( | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:739` Steady, generous sessions | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:843` of your listening was from \(Text( | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:876` \(Int(value.rounded()))% | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:892` The unread copy of every great\nbook is still a great book. | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsSections.swift:900` Back to Library | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsView.swift:91` Library | ReadingStatsScreen | same |
| `ReadingStats/ReadingStatsView.swift:103` Reading | ReadingStatsScreen | same |
| `RestoreMatchSheet.swift:45` Looks like '\(orphan.title)' | Slice 8 | owned by another slice |
| `RestoreMatchSheet.swift:49` Restore your progress, moments, and settings from iCloud? | Slice 8 | owned by another slice |
| `RestoreMatchSheet.swift:75` Restore from iCloud | Slice 8 | owned by another slice |
| `RestoreMatchSheet.swift:88` Add as new book | Slice 8 | owned by another slice |
| `RestoreMatchSheet.swift:99` iCloud match | Slice 8 | owned by another slice |
| `RestoreMatchSheet.swift:103` Cancel | Slice 8 | owned by another slice |
| `SettingsDesign.swift:157` Done | SettingsScreen / UnpagedTheme | same |
| `SettingsDesign.swift:315` · | SettingsScreen / UnpagedTheme | same |
| `SettingsView.swift:129` Membership & features. | SettingsScreen | same |
| `SettingsView.swift:134` Unpaged Plus | Purchases excluded | intentionally excluded |
| `SettingsView.swift:143` Apple Intelligence | Slice 9 | owned by another slice |
| `SettingsView.swift:144` Choose which local AI features to use | SettingsScreen | same |
| `SettingsView.swift:152` iCloud Sync | Slice 8 | owned by another slice |
| `SettingsView.swift:153` Manage your library sync settings | SettingsScreen | same |
| `SettingsView.swift:194` Support Unpaged. | SettingsScreen | same |
| `SettingsView.swift:209` Buy me a coffee | Purchases excluded | intentionally excluded |
| `SettingsView.swift:212` Optional one-time support. No features attached. | Purchases excluded | intentionally excluded |
| `SettingsView.swift:234` Your own shelf. | SettingsScreen | same |
| `SettingsView.swift:250` Audiobookshelf Server | SettingsScreen | same |
| `SettingsView.swift:288` Listening preferences. | SettingsScreen | same |
| `SettingsView.swift:297` On Resume | SettingsScreen | same |
| `SettingsView.swift:298` Rewind a bit when you press play after a break | SettingsScreen | same |
| `SettingsView.swift:307` Save Moment Offset | SettingsScreen | same |
| `SettingsView.swift:308` How far back the timestamp is set when you save a moment | SettingsScreen | same |
| `SettingsView.swift:317` Skip Backward | SettingsScreen | same |
| `SettingsView.swift:318` How far the back button jumps | SettingsScreen | same |
| `SettingsView.swift:327` Skip Forward | SettingsScreen | same |
| `SettingsView.swift:328` How far the forward button jumps | SettingsScreen | same |
| `SettingsView.swift:353` Appearance & tour. | SettingsScreen | same |
| `SettingsView.swift:362` Reset Onboarding | SettingsScreen | fixed in this slice |
| `SettingsView.swift:363` Show the welcome walkthrough again | SettingsScreen | fixed in this slice |
| `SettingsView.swift:372` Reset | SettingsScreen | same |
| `SettingsView.swift:376` Cancel | SettingsScreen | same |
| `SettingsView.swift:378` The onboarding walkthrough will start again from the beginning. | SettingsScreen | same |
| `SettingsView.swift:389` The fine print. | SettingsScreen | same |
| `SettingsView.swift:393` Privacy Policy | SettingsScreen | same |
| `SettingsView.swift:394` Terms of Use | SettingsScreen | same |
| `SettingsView.swift:427` Seeders & debug. | SettingsScreen | same |
| `SettingsView.swift:431` Seed Reading Activity · 7 days | SettingsScreen | same |
| `SettingsView.swift:435` Seed Reading Activity · 30 days | SettingsScreen | same |
| `SettingsView.swift:439` Seed Reading Activity · 113 days | SettingsScreen | same |
| `SettingsView.swift:443` Clear Reading Activity | SettingsScreen | same |
| `SettingsView.swift:613` Open To | SettingsScreen | same |
| `SettingsView.swift:616` The library that greets you when you launch Unpaged | SettingsScreen | same |
| `SettingsView.swift:623` Shelves | SettingsScreen | same |
| `SettingsView.swift:681` Appearance | SettingsScreen | same |
| `SettingsView.swift:682` Follow your iPhone, or always use light or dark | SettingsScreen | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:89` Read by \(narrator) | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:110` \(Text(duration).tracking(0.4))\(Text(rest).tracking(1.2)) | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:146` In your Library | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:151` · | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:188` Add to Library | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:204` Streams from your server — nothing is downloaded. | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBookDetailView.swift:228` About this book | ABSBookDetail | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:86` Library: \(viewModel.selectedLibrary?.name ??  | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:108` You're offline. | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:116` Can't reach \(hostLabel). | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:124` Your sign-in has expired. | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:132` Nothing to shelve yet. | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:140` Couldn't load your shelf. | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:149` This shelf is empty. | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:173` Continue Listening | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:177` Recently Added | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:181` All Books | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:196` No titles or authors match “\(viewModel.searchQuery)”. | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:253` Recently Added | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:261` Loading your library | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:275` Search titles & authors… | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:284` Search this library | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSBrowseView.swift:292` Clear search | ABSBrowse | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:66` Create one in Audiobookshelf under Settings → API Keys. | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:80` Your login stays on this iPhone, in the Keychain. | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:99` Cancel | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:113` Continue | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:118` Cancel | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:121` \(warning.host) uses plain http://. \(warning.message) | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:131` Bring your own shelf. | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSConnectView.swift:135` Connect your Audiobookshelf server to browse and stream your library in Unpaged. | ABSConnect | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:22` Audiobookshelf | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:55` Disconnect | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:60` Cancel | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:62` Unpaged forgets this login. Books you added stay in your Library, but won't play until you connect again. | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:94` Open in Shelves | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:102` Disconnect | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:141` Bring your own shelf. | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:143` Connect your Audiobookshelf server to browse and stream your library in Unpaged. | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:152` Connect a Server | ABSServerSettings | same |
| `Shelves/Audiobookshelf/ABSServerSettingsView.swift:161` Your login stays on this iPhone, in the Keychain. Books stream straight from your server; Unpaged sends your listening position back to it. | ABSServerSettings | same |
| `UnpagedPlusCard.swift:62` Unpaged Plus | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:106` \(store.trialDaysRemaining) \(store.trialDaysRemaining == 1 ?  | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:134` Checking purchases… | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:147` Apple Intelligence | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:148` Choose which local AI features to use | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:155` iCloud Sync | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:156` Manage your library sync settings | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:191` Manage Subscription | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:219` Retry loading plans | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:223` Restore purchases | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:234` Loading plans… | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:248` Restore purchases | Purchases excluded | intentionally excluded |
| `UnpagedPlusCard.swift:338` Retry | Purchases excluded | intentionally excluded |
