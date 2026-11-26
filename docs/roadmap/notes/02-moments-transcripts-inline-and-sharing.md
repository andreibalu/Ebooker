# Slice 02 notes (temporary)

## E2E & docs layer

Fixture (`Pageless/App/E2EFixtures.swift`): the listening book's "E2E Second Moment" now carries every
field (quote, mood, cast, categories, AI-named flag, notes, transcript). "lighthouse" appears only in its
transcript. "E2E First Moment" stays sparse (note and Dialogue only): the moment-edit, filter and pin
tests mutate or filter on it, and the Dialogue/Tense/Elizabeth filter assertions rely on Second not
matching them. No moment was added to the default fixture, because `library.e2e.ts` and
`smart-save.e2e.ts` assert "2 moments" and "3 moments". The plain-moment case comes from the existing
`-e2e-moment-search` set ("E2E Café" on the second book); the default second book has no moments, which
covers "export hidden".

Identifiers the tests rely on (agreed with the UI layer): `moment.quote.<label>`, `moment.meta.<label>`,
`momentSearch.snippet.<label>`, `moment.share`, `moment.transcript`, `moment.transcript.text`,
`moment.transcript.copy`, `audiobookDetail.exportMoments`, context-menu button "Share Moment".

Test-side findings against the working-tree UI (uncommitted when run):
- A `DisclosureGroup`'s `.accessibilityIdentifier` overrides its children's: every node inside the
  Transcript disclosure reports `moment.transcript`, and the export `ShareLink` in the moments
  disclosure label puts `audiobookDetail.exportMoments` on the "N moments" button too (two matches).
  The tests find those controls by role and text instead (`Transcript`, `Copy Transcript`,
  `Export Moments…`); the ids `moment.transcript.text`, `moment.transcript.copy` are not asserted.
- At accessibility-XXXL with Button Shapes the moments disclosure row squeezes: "N moments" ends as
  "2…" and the Filter capsule wraps a letter per line. `accessibility-layout.e2e.ts` ("keeps the
  moments header and its export control on one line") fails until the row gets room (for example the
  export control moves out of the label row, or the row wraps with `ViewThatFits`).
- Adding a Quote/Reflection category, a Marlow character and a Peaceful mood to the second fixture
  moment lengthened the filter sheet, pushing its Moods and Clear All below the half-height fold. The
  moments and extended-flows filter helpers now expand the sheet first.

Gaps by decision: quote-card pixels and exported Markdown text are not E2E-asserted (the share sheet's
file isn't readable from the host); `MomentMarkdownExporter` unit tests own the format.

Docs touched: `docs/ios/system-surfaces.md`, `docs/ios/ai.md`, `support.md`. Gists to update after merge:
the support Gist (mirrors `support.md`). Privacy policy and EULA unchanged: sharing is user-initiated and local.

## Core layer

Owns: `Pageless/Services/MomentSearch.swift`, `Pageless/Services/MomentMarkdownExporter.swift`, removal of `MomentSearch` from `Pageless/Views/MomentSearchView.swift`, and isolated unit tests in `PagelessTests/ServiceTests/`.

### Failure list (written before tests & implementation)
1. **Transcript search ignored or mis-ranked:** `MomentSearch.score` misses transcript-only words, fails multi-word queries split across label + transcript, or ranks transcript hits >= title/note hits.
2. **Diacritic/case mismatch:** `"cafe"` fails to match `"Café"` in `transcript` scoring or snippet extraction.
3. **Snippet windowing & ellipses:** `transcriptSnippet` fails to center ~8 words around the first match, adds leading `…` at index 0, adds trailing `…` at the end, or omits `…` when text is truncated.
4. **Redundant snippet:** `transcriptSnippet(for:query:)` returns a snippet when the matched word is already visible in `label`, `notes`, `quoteLine`, `characters`, `categories`, or `mood`, or windows around a visible word in a mixed query instead of the transcript-only word.
5. **Markdown ordering & formatting:** `MomentMarkdownExporter` misorders moments (must be pinned first, then `trackIndex`, then `time`), leaves unprefixed lines in multi-line blockquotes, keeps newlines in `## <label>`, escapes/strips `#`/`*`/`>`/emoji, emits empty/whitespace-only fields (`*by *`, `Tags:`, `Characters:`, `**Transcript:**`), or breaks single-blank-line block separation / trailing newline.
6. **Export filename & unavailable track:** `MomentsMarkdownExport` leaves `/` or `:` in `suggestedFileName`, or `markdown(for:)` crashes on an out-of-bounds `trackIndex` instead of `"Track unavailable"`.

## UI layer

Owns: `Pageless/Views/MomentQuoteCard.swift` (new), `Pageless/Views/MomentRow.swift`, `Pageless/Views/MomentEditSheet.swift`, and `Pageless/Views/AudiobookDetailView.swift` (`PlayerView.swift` needed no edits because new `MomentEditSheet` parameters default to `nil`).

- **Quote card (`MomentQuoteCard.swift`):** `MomentQuoteCardPayload` (`Sendable` value snapshot captured on `@MainActor`), lazy `MomentQuoteCardImage: Transferable` rendering PNG inside `DataRepresentation` only on share (scale 3, `.dynamicTypeSize(.large)`, `.colorScheme(.light)`, `.suggestedFileName("Unpaged Moment.png")`), and `MomentQuoteCardView` at fixed `360pt` width using explicit warm-cream light colors (`#F7F4ED` / `#FFFCF7` / ink / amber) so off-screen `ImageRenderer` never resolves dark-mode colors. Shows cover (`coverArtData` or `GeneratedCoverView`), serif italic quote (or label + note fallback), chapter · timestamp, book title/author, and Unpaged footer; never renders transcripts.
- **Row metadata & search snippet (`MomentRow.swift`):** Search layout renders `MomentSearch.transcriptSnippet(for:query:)` with a `waveform` glyph, `MomentSearch.highlighted` styling, `lineLimit(2)`, and `momentSearch.snippet.<label>`. Book-detail `editableBody` adds serif italic `quoteLine` (`moment.quote.<label>`) and a non-wrapping single-line metadata strip (`moment.meta.<label>`, Dynamic Type capped at `.accessibility1`) with mood pill, up to 3 category/character chips, `+N` overflow, and `sparkles` when `aiGeneratedName`; renders nothing extra when those fields are absent, and preserves swipe-to-delete, pin, tap-to-edit, and play. Context menu adds `ShareLink` labeled `"Share Moment"`.
- **Edit sheet (`MomentEditSheet.swift`):** Adds optional `transcript: String? = nil` and `shareCard: MomentQuoteCardImage? = nil`. Shows a toolbar `ShareLink` (`moment.share`) only when editing an existing moment, and a collapsed `DisclosureGroup("Transcript")` (`moment.transcript`) at the bottom of the form with selectable text (`moment.transcript.text`) and a `Copy Transcript` button (`moment.transcript.copy`, `UIPasteboard`, brief `"Copied"` state) when `transcript` is non-empty.
- **Per-book Markdown export (`AudiobookDetailView.swift`):** Adds `exportMomentsShareLink` (`ShareLink` with `MomentsMarkdownExport(book:)`, `audiobookDetail.exportMoments`) in the moments section header when `!audiobook.moments.isEmpty`. Caps the moments disclosure header row at `.dynamicTypeSize(...DynamicTypeSize.xLarge)` and keeps `Filter` single-line (`fixedSize(horizontal: true, vertical: false)`) so the header stays on one line at accessibility text sizes and Button Shapes.
- **Visual verification (`/tmp/unpaged-slice02-ui/`):** Verified on iPhone 17 (`82B346D2-A6F4-4CAE-886F-CE293734AF67`) in light, dark, and `accessibility-extra-large` modes, plus expanded Transcript, Moment Share sheet, Export Moments share sheet, and both rendered 3x quote-card PNG variants.

