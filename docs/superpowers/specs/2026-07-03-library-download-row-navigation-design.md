# Library Download Row Navigation Design

## Goal

Make title/status area of each LibriVox download row in Library open same
LibriVox catalog detail used by Free Books, including description and sample.

## Behavior

- Library passes selection callback to shared `LibriVoxDownloadSection`.
- Callback resolves row `catalogID` from local `LibriVoxBook` cache through
  existing `BrowseLibriVoxViewModel.catalogBook` resolver.
- Matching book opens existing `LibriVoxBookDetailView` in Library navigation
  stack.
- Missing local catalog record performs no navigation.
- Cancel, retry, and dismiss controls remain independent and never navigate.
- Free Books and Library row appearance remains unchanged.

## Testing

- Reuse resolver coverage for matching and missing catalog IDs.
- Add focused coverage for shared selection routing if extractable without UI
  implementation coupling.
- Run focused tests, full `PagelessTests`, and physical-device build.

## Out of Scope

- Navigating to `AudiobookDetailView`.
- Remote fetch solely for navigation.
- Download-row visual changes.
