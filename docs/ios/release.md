# iOS release and submission

Read this before bumping a version, archiving, uploading to App Store Connect, starting an Xcode Cloud build or submitting for review. Releases go out from the command line, not Xcode's Organizer.

## Credentials

The repo is public. App Store Connect credentials live only on the owner's Mac: `~/.appstoreconnect/issuer_id` and `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` (the key id is the filename). Several keys may be present; `scripts/xcode-cloud-build.sh` uses the first one that can read the app, and `ASC_KEY_ID` picks one explicitly. Key ids, issuer ids and key contents never enter a commit, a log or a PR.

App Store Connect app id: `6761081641`.

## Signing App Store Connect requests

Sign the ES256 JWT the way `scripts/xcode-cloud-build.sh` does: `openssl dgst -sha256 -sign` over `header.payload`, then convert openssl's DER `SEQUENCE{INTEGER r, INTEGER s}` to raw `r||s` (32 bytes each) with stdlib Python. That needs nothing beyond the system's openssl and Python. Off-the-shelf snippets assume `jwt` or `cryptography` modules, which the host may not have.

## Steps

1. **Version.** Bump `MARKETING_VERSION` in `project.pbxproj` and `VERSION` together. Set `CURRENT_PROJECT_VERSION` above the highest build App Store Connect already holds for that marketing version.
2. **Tests.** Run the full native E2E suite and the retained Swift tests, serially (see `AGENTS.md` → Testing). All green.
3. **Archive and export.** `xcodebuild archive` (Release, `-destination generic/platform=iOS`), then `xcodebuild -exportArchive` with an `ExportOptions.plist` of `method: app-store-connect`, `signingStyle: automatic`, `manageAppVersionAndBuildNumber: false`.
4. **Upload.** `xcrun altool --validate-app`, then `--upload-app`, against `<export-dir>/Pageless.ipa` (the file, not the export directory).
5. **Submit.** Wait for the build's `processingState` to reach `VALID`, attach it to the version, and submit.

The App Store Connect web UI is a slow single-page app that often renders blank in a narrow browser pane. The REST API is faster for the last mile: `PATCH /v1/appStoreVersions/{id}/relationships/build`, add the version to the open `reviewSubmission`, then set `submitted: true`. An in-app purchase submitted with the version becomes a second `reviewSubmissionItem` on the same submission.

Screenshot display types in the API lag device names: the 6.9" set (1320×2868) has uploaded as `APP_IPHONE_67` while `APP_IPHONE_69` was rejected, and the 6.5" set is `APP_IPHONE_65`. If an upload is rejected for its display type, try the neighbouring type.

## Beyond the build

- The IAP review screenshot and review notes match the shipping UI. A screenshot that still shows removed copy is a review risk.
- The public docs (`support.md`, `privacy-policy.md`, `EULA.md`) and their Gists reflect the release (see `AGENTS.md` → Hard rules).
- Release notes are saved on the version.
- `store-listing/` holds the drafted listing text for the next version.

## Xcode Cloud

Xcode Cloud builds start only when the owner asks for a TestFlight or App Store build; pushes start nothing. `scripts/xcode-cloud-build.sh` with no argument lists each workflow, whether it starts on push, and the branch it builds. With a workflow name it starts that workflow on its branch: `External` tests and archives for the App Store, `Internal` archives for internal TestFlight.

`ci_scripts/ci_post_clone.sh` rewrites `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the cloned pbxproj on every Xcode Cloud build, from `VERSION`, the branch and `CI_BUILD_NUMBER`; read it for the exact rule. Xcode Cloud therefore ignores the committed pbxproj values (they matter for local archives) and `VERSION` decides the marketing version. Once a version is approved, bump `VERSION` (and the pbxproj, for local archives) before the next build, or its upload fails with ITMS-90186 / ITMS-90062.
