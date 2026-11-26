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

Gaps by decision: quote-card pixels and exported Markdown text are not E2E-asserted (the share sheet's
file isn't readable from the host); `MomentMarkdownExporter` unit tests own the format.

Docs touched: `docs/ios/system-surfaces.md`, `docs/ios/ai.md`, `support.md`. Gists to update after merge:
the support Gist (mirrors `support.md`). Privacy policy and EULA unchanged: sharing is user-initiated and local.
