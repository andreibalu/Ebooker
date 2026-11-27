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


## Review round 1

Supersedes the UI-layer and E2E notes above where they differ (export control placement, ids).

| # | Finding | Fix |
| --- | --- | --- |
| 1 | Eager share/export work in `body` | `313867c` (quote card), `16877c5` (Markdown export): both Transferables hold `PersistentIdentifier` + `ModelContainer` + short strings and resolve cover, tracks, moments and the export date in the transfer closure on the main actor. The edit sheet passes a `MomentQuoteCardDraft` of three strings. |
| 2 | Snippet ignored book title and author | `54cb549` |
| 3 | Metadata scored 0 | `54cb549`: metadata scores 2 with notes and quote, transcript stays 1. `docs/ios/system-surfaces.md` updated in `7c0427b`. |
| 4 | Markdown export emitted user text raw | `16877c5`: line-start markers escaped, hard breaks, inline escapes in headings, chapter line, title, author and tags, filename collapses newlines and drops leading dots. |
| 5 | Doubled opening quote | `313867c`: `MomentQuoteText` strips double quote marks (straight and curly); the card payload and `MomentRow` share it. Single quotes stay: a trailing one is usually an apostrophe. |
| 6 | Duplicate chip ids | `2f5904c`: enumerated offsets. |
| 7 | Large-text failures | `2f5904c`: the disclosure label holds only the count; Filter and Export moved into the first row of the expanded list (`ViewThatFits`, stacked when they don't fit). Tests: the header test was partly wrong (`getByText('Filter')` matched the capsule's icon, 24pt wide), and the row test assumed the quote was on screen at XXXL, where the row outgrows the screen. Both fixed in `393099e`. |
| 8 | Id collisions | `2f5904c`: transcript id on the disclosure label only (it reaches the button and its text, so the test takes `.first()`); the export ShareLink left the label. Tests use the ids again (`393099e`). |
| 9 | Truncated chips | `2f5904c`: `ViewThatFits` over three, two, one, zero chips; the rest fold into "+N"; the mood pill is in every variant. |
| 10 | support.md wording | `7c0427b`: "open the book's moments list and tap Export Moments… at the top". The support Gist needs the same edit. |
| 11 | COVERAGE section | `7c0427b` |

Decision: Export is visible only when the moments list is expanded (it is collapsed by default). The alternative, an icon inside the disclosure label, brought back both the squeeze and the id collision.

Results: `moments` 8/8, `moment-search` 12/12, `accessibility-layout` 5/5, `extended-flows` 11/12 (the EQ preset test fails on `main` as well). Unit tests: 392 run, one failure (`coffeeTipSucceedsRepeatsAndFinishesEachTransaction`), also failing on `main` in a full run.

## Review round 2

| # | Finding | Fix |
| --- | --- | --- |
| 1 | Share on a deleted record crashed (`model(for:)` returns a model for a deleted row) | `9a3dfe1`: `ModelContext.existingModel(_:id:)` (registered model, else a fetch by id, `isDeleted` counts as missing) used by the quote card and by the Markdown export's book lookup; both throw, so the share yields nothing. |
| 2 | Metadata strip could overflow at 320pt with large text | `b9d4c0a`: the zero-chip variant is not `fixedSize`; the mood pill truncates, "+N" and the sparkles keep their width. |
| 3 | Third chip hidden while the row had room | `b9d4c0a`: the text column fills the row (`maxWidth: .infinity`), the `Spacer` is gone, so `ViewThatFits` sees the real width. |
| 4 | VoiceOver read "Share, Export Moments…" | `a63ec4f`: the capsule's icon is hidden from accessibility; the id stays. |
| 5 | Markdown escaping | `5527683`: spaced `_ _ _` / `* * *` / `- - -` rules and `-` setext underlines are escaped; `3.14`, `-5`, `-ish`, `+1`, `*emphasis*` stay as typed (list and ordered markers need whitespace or the line end after them); a closing `#` run in a heading or title is escaped. `#`, `>`, `=`, backtick and `~` at a line start are still always escaped. |
| 6 | No test rendered the quote card | `9a3dfe1`: `MomentQuoteCardRenderTests` (PNG data from a saved moment with a draft, payload takes the draft, deleted moment and deleted book throw). COVERAGE lines corrected in `b5d00cb`. |
| 7 | Slice 02 bullets in the 1.5.0 section | `b5d00cb` |
| 8 | Misleading test name | `4751209` |

Decisions: the card's own pixels are still only checked by eye (the share file isn't readable from the host). 320pt: no 320pt simulator runtime exists and Display Zoom can't be set from `simctl`, so a throwaway unit test rendered the real `MomentRow` at 320pt width with `.accessibility1`, Bold Text and "Inspirational" plus "+3" and sparkles: the mood pill truncated and the rest stayed whole. That test was not kept.

Results: unit tests 399 run, one failure (`coffeeTipSucceedsRepeatsAndFinishesEachTransaction`, the known flake). `moments` 8/8, `moment-search` 12/12, `accessibility-layout` 5/5 on "Unpaged e2e" (iOS 27.0). Screenshots outside Git in `/tmp/unpaged-slice02-fix2/`.
