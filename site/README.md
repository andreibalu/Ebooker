# Unpaged website

Static marketing site for the Unpaged iPhone app, published to GitHub Pages by
`.github/workflows/pages.yml` on pushes to `main` that touch `site/` or the legal docs.

```bash
node site/build.mjs                 # writes site/dist (no npm install needed)
cd site && npm run preview          # local build + server on http://127.0.0.1:4400
cd site && npm install && npm run assets   # regenerate public/ images (sharp)
```

## Layout

| Path | Role |
| --- | --- |
| `build.mjs` | Zero-dependency build: pages, legal docs, sitemap, robots, link check |
| `site.config.json` | Production URL, App Store URL (structured data), campaign-tagged App Store link (badges and buttons), app id. `SITE_URL` overrides the URL |
| `src/content.mjs` | All English copy, including the `ui` strings and the moment anatomy |
| `src/guides.mjs` | The two setup guides (English), the translated nav label and home strip |
| `src/i18n/*.mjs` | de, es, fr, it, pt-br partial overrides, deep-merged over English (arrays replace wholesale) |
| `src/style.css`, `src/app.mjs` | The one stylesheet and the one script (tabs, anatomy, reduced-motion toggle) |
| `public/` | Committed images and fonts, copied as is |
| `tools/assets.mjs` | Rebuilds `public/` from `screenshots/public/screenshots/en/` and the app icon |
| `tools/serve.mjs` | Local server for `dist/`, with the 404 fallback |

Pages: home and `plus/` per locale (English at the root, others under `/<code>/`),
a root `404.html` that swaps in the visitor's locale by path prefix, `guides/` (an index and two
English setup guides, content in `src/guides.mjs`), and
`support/`, `privacy/`, `terms/` rendered from the repo-root `support.md`,
`privacy-policy.md` and `EULA.md`. The build fails on a broken internal link.

## Design rules

- Colors follow the app: cream `#f7f3ed`, paper `#fffcf7`, sand `#efe8dc`, ink `#15202b`,
  amber `#cc8632` / `#e49a21` (text `#9a5c16`), navy `#122231` for the closing section.
- Type: self-hosted Newsreader (OFL) for display, the system sans for text.
- Imagery is real app screenshots only. No invented testimonials, ratings or usage numbers.
- The moment anatomy shows how on-device Apple Intelligence fills each moment field.
  Its excerpt, results and chips stay English (the app is English-only) and carry `lang="en"`.
  Field claims must match `MomentNamingService`: ten categories, eight moods,
  quotes kept only when they appear in the transcript.
- Under 1100px the anatomy stacks: the stage stays sticky at one fixed height for
  all seven steps, the transcript is a scrolling window that takes the room the card
  leaves, and the card accumulates (finished fields shrink to one line, the field in
  play shows in full, the card appears at step 3). There are no cables on the stacked
  layout. The active step is the one a little below the stage's bottom edge.
- Every animation has a static state for `prefers-reduced-motion` and the footer toggle.

## Guides and their media

Guide text is English only and carries `lang="en"` on localized pages; the nav label and the home strip are translated.
Write only what the app does. Every step and limit comes from the code, `docs/ios/audiobookshelf.md` or `support.md`, and the
steps were run in the Simulator. Quote no prices and no iCloud or Plus terms there.

Media in `public/guides/` are real captures from the iOS Simulator (iPhone 18 Pro, iOS 27, light appearance, status bar set to
9:41 with `simctl status_bar override`). Recording and screenshots use `xcrun simctl io <udid> recordVideo` and `screenshot`:

- **Audiobookshelf guide:** a DEBUG fixture launch (`-e2e-fixture -e2e-online`) against `e2e/support/fake-audiobookshelf.ts`, run from
  a scratch copy with public-domain titles, a user named `reader`, and 30-minute tracks, so the recording shows no fixture names.
  The address is `127.0.0.1`, which the video caption says.
- **M4B guide:** a four-chapter M4B made with `say` and `ffmpeg` (the narration is near-silent so it stays quiet on the host), imported with
  `-e2e-import -e2e-import-file`, which stands in for the Files picker, on a library emptied by `-guide-clean-library`.
- Video: H.264, muted, 402×874, `crf 25`, `+faststart`, about 0.4 MB each; screenshots are 720×1565 WebP. Keep each video well under 3 MB.
- Re-record when the screens in a guide change, and update the "Written against" line in `src/guides.mjs`.
