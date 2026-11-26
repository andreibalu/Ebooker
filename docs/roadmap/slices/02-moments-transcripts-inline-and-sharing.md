# Slice 02: Moments Transcripts, Inline Metadata & Quote Sharing

## Goal
Make Unpaged's flagship Moments feature feel genuinely rich and portable: actually search and display the spoken transcripts already being stored, surface AI-extracted quotes/moods/tags inline on each book's moment list, and add editorial quote card sharing plus per-book Markdown export.

## Verified Current State
- **Stored transcripts are dead data:** `docs/ios/ai.md:35` says *"The transcript is kept so moment search finds it"*, and `PlayerViewModel.swift:246, 273, 291` persists `moment.transcript`. Yet `MomentSearch.score` (`Pageless/Views/MomentSearchView.swift:14-22`) only searches `label`, `book.title`, `book.author`, `notes`, `quoteLine`, `characters`, `categories`, and `mood`—never `moment.transcript`. No view displays `moment.transcript`.
- **Hidden metadata in book detail:** `MomentRow.editableBody` (`Pageless/Views/MomentRow.swift:225-242`) renders only `label`, `time`, and 2 lines of `notes`, completely hiding `quoteLine`, `categories`, `mood`, `characters`, and `aiGeneratedName` until you open `MomentEditSheet`.
- **Zero sharing or export:** No `ShareLink` or `UIActivityViewController` exists anywhere in `Pageless/`.

## Scope

### 1. Transcript Search & Inspection
- Include `moment.transcript` in `MomentSearch.score` (`MomentSearchView.swift`) at a lower weight than titles/notes (e.g., weight `1` vs `10`/`2`) so title/note hits still rank first while spoken-word queries reliably match.
- When a search query matches inside `moment.transcript` (and not already visible in label/note/quote), render a compact 2-line centered snippet around the first matched word with amber `MomentSearch.highlighted` styling in `MomentRow`'s search layout.
- Add a collapsible **"Transcript"** disclosure section in `MomentEditSheet` (read-only, selectable text + Copy button) when `moment.transcript` is non-empty.

### 2. Inline Rich Metadata on `MomentRow`
- In `MomentRow.editableBody` (`Pageless/Views/MomentRow.swift`):
  - Show `quoteLine` in subtle italic/serif styling (max 2 lines) when present.
  - Show a compact single-line metadata strip (mood pill, up to 2–3 category/character chips, and subtle sparkle indicator when `aiGeneratedName` is true) without bloating row height or breaking Dynamic Type / Button Shapes.
- Keep `MomentRow` swipe-to-delete, pin toggle, tap-to-edit, and play button behavior intact.

### 3. Quote Card Sharing & Per-Book Markdown Export
- **Shareable Quote Card:** Add a **"Share Moment"** action to `MomentRow`'s context menu and `MomentEditSheet`'s toolbar. Render a clean, high-resolution editorial card via `ImageRenderer` (book cover or `GeneratedCoverView`, quoted line or moment label + note, chapter/timestamp, book title & author, subtle Unpaged footer) respecting light/dark or a warm cream editorial style, shared through `ShareLink`.
- **Per-Book Markdown Export:** Add **"Export Moments…"** in `AudiobookDetailView`'s moments section header / `…` menu (shown when the book has ≥1 moment). Generate clean Markdown (book title, author, moments sorted chronologically or pinned-first with chapter, timestamp, quote blockquote, notes, tags/characters, and optional transcript) shared via `ShareLink` (as `.md` file / text).

## Decision Gate (Step 3)
Routine on settled rules (no schema or purchase changes); skip Step 3 unless adding a new persisted preference.

## Suggested Layer Split
- **Core / Formatting:** Extract pure helpers for transcript snippet extraction (`MomentSearch`) and Markdown export formatting (`MomentMarkdownExporter` in `Pageless/Utilities/` or `Pageless/Services/`) + targeted unit tests in `PagelessTests/`.
- **UI:** `Pageless/Views/MomentRow.swift`, `Pageless/Views/MomentSearchView.swift`, `Pageless/Views/MomentEditSheet.swift`, `Pageless/Views/AudiobookDetailView.swift`, plus a `MomentQuoteCardView` renderer view.
- **E2E & Docs:** `e2e/tests/moments.e2e.ts` (transcript search match & snippet, inline quote/tags visible on `MomentRow`, transcript disclosure in edit sheet, share/export controls reachable), `docs/ios/system-surfaces.md` and `docs/ios/ai.md`.

## Verification Plan
- **Unit tests (`PagelessTests`):** `MomentSearch` scoring & snippet windowing with diacritics/multi-word queries in `transcript`; `MomentMarkdownExporter` output format with quotes, notes, missing fields, and special characters.
- **E2E & Visual (`verify-ebooker`):** Seed a book with moments containing `quoteLine`, `mood`, `categories`, `characters`, and `transcript`; verify search finds a transcript-only word, verify `MomentRow` renders quote + pills cleanly at standard & accessibility text sizes, verify Share/Export sheets present cleanly.
- **Docs:** Update `docs/ios/system-surfaces.md` → *Library moment search* and `docs/ios/ai.md`.
