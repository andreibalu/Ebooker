# iOS release and submission

Read this before bumping a version, archiving, uploading to App Store Connect, starting an Xcode Cloud build or submitting for review. Releases go out from the command line, not Xcode's Organizer.

## Credentials

The repo is public. App Store Connect credentials live only on the owner's Mac: `~/.appstoreconnect/issuer_id` and `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` (the key id is the filename). Several keys may be present; `scripts/xcode-cloud-build.sh` uses the first one that can read the app, and `ASC_KEY_ID` picks one explicitly. Key ids, issuer ids and key contents never enter a commit, a log or a PR.

App Store Connect app id: `6761081641`.

## Signing App Store Connect requests

`scripts/asc-api.sh METHOD PATH [BODY]` makes one signed call and prints the JSON, including Apple's `errors` array on failure. Source it to get `api` and `json` in a script, as `scripts/xcode-cloud-build.sh` does. Percent-encode brackets in query strings (`filter%5Bversion%5D=126`), because curl treats bare `[ ]` as a glob.

It signs the ES256 JWT like this: `openssl dgst -sha256 -sign` over `header.payload`, then convert openssl's DER `SEQUENCE{INTEGER r, INTEGER s}` to raw `r||s` (32 bytes each) with stdlib Python. That needs nothing beyond the system's openssl and Python. Off-the-shelf snippets assume `jwt` or `cryptography` modules, which the host may not have.

## Steps

The usual release ships `main` through Xcode Cloud: steps 1 and 2, then `scripts/xcode-cloud-build.sh External`, then step 5. Steps 3 and 4 are for a local archive.

1. **Version.** Check first whether the current version is live (`appStoreState` `READY_FOR_SALE`). If it is, the next release needs a bump. Bump `MARKETING_VERSION` in `project.pbxproj` and `VERSION` together. Set `CURRENT_PROJECT_VERSION` above the highest build App Store Connect already holds for that marketing version.
2. **Tests.** Run the full native E2E suite and the retained Swift tests, serially (see `AGENTS.md` → Testing), on the dedicated `Unpaged e2e` simulator. All green. These local runs are the release gate (see Xcode Cloud below):

   ```bash
   export E2E_SIMULATOR_UDID=<Unpaged e2e udid> E2E_BUILD_DIR=<scratch>/e2e-build E2E_TELEMETRY_DISABLED=1
   npm --prefix e2e ci && npm --prefix e2e run build:install && npm --prefix e2e run typecheck && npm --prefix e2e test
   xcodebuild -project Pageless.xcodeproj -scheme Pageless -destination "platform=iOS Simulator,id=$E2E_SIMULATOR_UDID" \
     -configuration Debug -derivedDataPath <scratch>/dd -resultBundlePath <scratch>/tests.xcresult test -parallel-testing-enabled NO
   ```

   The build and E2E suite take about 40 minutes, and the Swift tests a few more. `xcrun xcresulttool get test-results summary --path <scratch>/tests.xcresult` gives the Swift totals.
3. **Archive and export.** `xcodebuild archive` (Release, `-destination generic/platform=iOS`), then `xcodebuild -exportArchive` with an `ExportOptions.plist` of `method: app-store-connect`, `signingStyle: automatic`, `manageAppVersionAndBuildNumber: false`.
4. **Upload.** `xcrun altool --validate-app`, then `--upload-app`, against `<export-dir>/Pageless.ipa` (the file, not the export directory).
5. **Submit.** Wait for the build's `processingState` to reach `VALID`, attach it to the version, and submit. Check that the build's `preReleaseVersion` is the new marketing version before attaching it.

The App Store Connect web UI is a slow single-page app that often renders blank in a narrow browser pane. The REST API is faster for the last mile:

1. `POST /v1/appStoreVersions` (`platform: IOS`, `versionString`, `releaseType: AFTER_APPROVAL`) once the live version needs a successor. The new version copies description, keywords, promotional text and screenshots from the live one, in every locale. What's New starts empty.
2. `PATCH` each `appStoreVersionLocalizations` entry with `whatsNew`. Write it for every locale the listing has, following the localization rules in `store-listing/README.md`.
3. `PATCH /v1/appStoreVersions/{id}/relationships/build`.
4. Reuse the open `reviewSubmission`, or `POST /v1/reviewSubmissions` when none is open. Then `POST /v1/reviewSubmissionItems` with the version. The first item POST right after creating a submission can fail once, and a retry succeeds.
5. `PATCH` the submission with `submitted: true`. The version reads `WAITING_FOR_REVIEW` once it is in. An in-app purchase submitted with the version becomes a second `reviewSubmissionItem` on the same submission.

Screenshot display types in the API lag device names: the 6.9" set (1320×2868) has uploaded as `APP_IPHONE_67` while `APP_IPHONE_69` was rejected, and the 6.5" set is `APP_IPHONE_65`. If an upload is rejected for its display type, try the neighbouring type.

## Beyond the build

- The IAP review screenshot and review notes match the shipping UI. A screenshot that still shows removed copy is a review risk.
- The public docs (`support.md`, `privacy-policy.md`, `EULA.md`) and their Gists reflect the release (see `AGENTS.md` → Hard rules).
- Release notes are saved on the version.
- `store-listing/` holds the drafted listing text for the next version.

## Xcode Cloud

Xcode Cloud builds start only when the owner asks for a TestFlight or App Store build; pushes start nothing. `scripts/xcode-cloud-build.sh` with no argument lists each workflow, whether it starts on push, and the branch it builds. With a workflow name it starts that workflow on its branch: `External` tests and archives for the App Store, `Internal` archives for internal TestFlight.

The `External` workflow builds `main`, so merge the version bump before starting it. An External run has three actions, and only the archive decides a release:

- `Test - iOS` has failed on every run since at least build 121, in `StoreKitTransactionTests` and on a 10-minute timeout. The local serial run in step 2 is the gate. Don't hold a release on this action. Read its failures through `/v1/ciBuildActions/{id}/issues` (the action named exactly `Test - iOS`, not the TestFlight one).
- `Archive - iOS` uploads the build. Once it succeeds, the build appears under `/v1/builds` and processes to `VALID` within minutes.
- `TestFlight External Testing - iOS` can stay `RUNNING` for a long time, and it leaves the run without a completion status. Poll the build's `processingState`, not the run.

`ci_scripts/ci_post_clone.sh` rewrites `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the cloned pbxproj on every Xcode Cloud build, from `VERSION`, the branch and `CI_BUILD_NUMBER`; read it for the exact rule. Xcode Cloud therefore ignores the committed pbxproj values (they matter for local archives) and `VERSION` decides the marketing version. Once a version is approved, bump `VERSION` (and the pbxproj, for local archives) before the next build, or its upload fails with ITMS-90186 / ITMS-90062.
