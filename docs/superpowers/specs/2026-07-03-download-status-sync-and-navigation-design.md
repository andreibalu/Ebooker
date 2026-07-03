# Download Status Sync and Navigation Design

## Goal

Keep in-app LibriVox download state synchronized with background download and
Live Activity state, make Free Books download rows compact and naturally
scrolling, and route row taps to corresponding book detail.

## Root Cause

`PagelessRootView.init` constructs `LibriVoxDownloadManager` while initializing
`@State`. SwiftUI may recreate root view values while retaining existing state.
Each discarded manager still replaces coordinator event sink during init. The
visible manager remains in `preparing` or `cancelling`, while discarded manager
receives coordinator progress and updates Live Activity.

## Architecture

`AppDelegate` owns one process-lifetime `LibriVoxDownloadManager`, adjacent to
its existing process-lifetime background coordinator. Root view receives and
injects that stable manager without constructing another manager. Coordinator
gets one event sink for visible manager lifetime.

No polling, duplicate state mirroring, or timer-based reconciliation is added.

## Free Books Layout

Remove standalone fixed-height download `ScrollView` above catalog content.
Place shared `LibriVoxDownloadSection` at top of Free Books content scroll,
after search/filter status and before hero/catalog sections. Rows use existing
Library compact treatment: title, precise status, progress, and trailing action.
Section scrolls away with catalog and never stays pinned.

Spacing remains consistent with existing Open Shelf layout. Section has no
reserved height when empty and no oversized blank region when one or two jobs
exist.

## Navigation

Download row title/status area acts as navigation control. It resolves
`catalogID` against local `LibriVoxBook` cache and opens existing
`LibriVoxBookDetailView`, preserving description, sample, download controls,
and alternatives.

Trailing cancel/retry/dismiss controls remain independent and do not trigger
navigation. If no local catalog record exists, row remains visible but
non-navigable. No unavailable-detail screen is introduced.

## State and Error Behavior

- First coordinator progress changes visible state from `preparing` to
  `downloading` with track and fractional progress.
- Coordinator cancellation event removes visible row after cleanup.
- Failure remains visible with retry and dismiss actions.
- Live Activity continues using same manager snapshot aggregation.
- Restored jobs retain navigation when matching cached catalog record exists.

## Testing

- Regression coverage proves stable owner does not replace coordinator sink
  through view reconstruction.
- Manager tests cover progress and cancellation delivery to visible instance.
- Navigation resolver tests cover matching and missing catalog records.
- Presentation tests preserve compact phase/status behavior.
- Run focused device tests, full `PagelessTests`, and device build.

## Out of Scope

- New download queue semantics.
- Remote catalog fetch solely for row navigation.
- Live Activity visual redesign.
- Changes to Library download-row placement.
