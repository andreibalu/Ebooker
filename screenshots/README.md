# Unpaged App Store screenshot generator

Reproducible Bun/Next.js release tooling for composing Unpaged marketing slides
and exporting App Store screenshots. Generator source lives in
`src/app/page.tsx`.

## Setup

From this directory:

```bash
bun install --frozen-lockfile
bun run check
```

`check` runs TypeScript validation and a production build. Run the local preview
with:

```bash
bun run dev
```

Open <http://localhost:3000>.

## Export

1. Choose an iPhone size in the toolbar.
2. Use `Export` on one reviewed slide. Use `Export All` only after every referenced
   capture has an approved, non-private input.
3. Keep downloaded PNGs outside the repository; browser exports are release
   outputs and are not source inputs.

Supported App Store screenshot sizes:

- 1320 × 2868 (6.9-inch)
- 1284 × 2778 (6.5-inch)
- 1206 × 2622 (6.3-inch)
- 1125 × 2436 (6.1-inch)

## Reviewed inputs

Reusable inputs belong under `public/`. Current reviewed inputs are the app icon,
iPhone mockup, and the safe English marketing captures under
`public/screenshots/en/`. Two original captures containing a personal cat photo
are intentionally excluded: `library.png` and `icloud-library.png`. Do not add
raw device captures, personal data, unclear-license assets, `.next`,
`node_modules`, or exported PNGs without review.

Before adding an asset, inspect its visual content, confirm its license/ownership,
and verify it contains no personal information. Keep source/config/lockfile
changes versioned; keep generated and private material ignored.

## Validation

```bash
bun install --frozen-lockfile
bun run typecheck
bun run check
bun run build
git diff -- screenshots/bun.lock
git status --short --ignored screenshots
```

`bun.lock` must remain unchanged during frozen validation. Use only approved
inputs when exporting release screenshots.
