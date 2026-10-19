// Composes the Audiobookshelf custom product page slides (1320 × 2868, the 6.9" set) from raw
// simulator captures, in the style of src/app/page.tsx: cream background, caption, iPhone mockup.
//
//   node screenshots/abs-demo/compose.mjs <captures-dir> <out-dir>
//
// <captures-dir> holds the PNGs named in `slides` below, captured at 1320 × 2868.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [captures, out] = process.argv.slice(2).map((p) => resolve(p));
if (!captures || !out) throw new Error('usage: compose.mjs <captures-dir> <out-dir>');
mkdirSync(out, { recursive: true });
const here = dirname(fileURLToPath(import.meta.url));
const dataURL = (path) => `data:image/png;base64,${readFileSync(path).toString('base64')}`;
const mockup = dataURL(join(here, '..', 'public', 'mockup.png'));
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

export const slides = [
  { file: '01-abs-shelf.png', label: 'Audiobookshelf', headline: 'Your server’s library,<br>on your iPhone.',
    sub: 'Sign in with a password or an API key and browse the books you already host.' },
  { file: '04-abs-player.png', label: 'Listen', headline: 'Pick up right where<br>you left off.',
    sub: 'Unpaged resumes from your server’s position and sends your progress back as you listen.' },
  { file: '05-abs-download.png', label: 'Offline', headline: 'Download books<br>for offline listening.',
    sub: 'Take them on a flight or out of range. Progress catches up with your server later.' },
  { file: '02-abs-series.png', label: 'Browse', headline: 'Series in reading<br>order.',
    sub: 'Browse by series, collections, authors and narrators, even offline from your cached library.' },
];

const W = 1320, H = 2868;
// Mockup geometry, from src/app/page.tsx.
const MK_W = 1022, MK_H = 2082, SC = { l: 52 / MK_W, t: 46 / MK_H, w: 918 / MK_W, h: 1990 / MK_H, rx: 126 / 918, ry: 126 / 1990 };
const phoneW = Math.min(0.86, 0.72 * (H / W) * (MK_W / MK_H)) * W;
const phoneH = phoneW * (MK_H / MK_W);

for (const [index, slide] of slides.entries()) {
  const screen = dataURL(join(captures, slide.file));
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;width:${W}px;height:${H}px;overflow:hidden}
    body{position:relative;font-family:-apple-system,"SF Pro Display",system-ui,sans-serif;
      background:linear-gradient(90deg,rgba(255,255,255,.08) 0%,transparent 44%,rgba(0,0,0,.04) 100%),linear-gradient(170deg,#F6F1EA 0%,#EFE6D8 100%)}
    .cap{position:absolute;top:${W * 0.075}px;left:${W * 0.075}px;right:${W * 0.075}px}
    .label{font-size:${W * 0.03}px;font-weight:700;text-transform:uppercase;color:#B8744A;margin-bottom:${W * 0.025}px}
    .head{font-size:${W * 0.078}px;font-weight:700;line-height:1.04;color:#1A1410}
    .sub{margin-top:${W * 0.04}px;font-size:${W * 0.036}px;color:#7C6F62;max-width:${W * 0.86}px;line-height:1.45}
    .phone{position:absolute;top:${W * 0.5}px;left:${(W - phoneW) / 2}px;width:${phoneW}px;height:${phoneH}px;
      filter:drop-shadow(0 30px 60px rgba(26,20,16,.18))}
    .screen{position:absolute;left:${SC.l * 100}%;top:${SC.t * 100}%;width:${SC.w * 100}%;height:${SC.h * 100}%;
      border-radius:${SC.rx * 100}% / ${SC.ry * 100}%;overflow:hidden;z-index:10}
    .phone>img{display:block;width:100%;height:100%}
    .screen img{display:block;width:100%;height:100%;object-fit:cover;object-position:top}
  </style></head><body>
    <div class="cap"><div class="label">${slide.label}</div><div class="head">${slide.headline}</div><div class="sub">${slide.sub}</div></div>
    <div class="phone"><img src="${mockup}"><div class="screen"><img src="${screen}"></div></div>
  </body></html>`;
  const name = `${String(index + 1).padStart(2, '0')}-${slide.file.replace(/^\d+-/, '')}`;
  const page = join(out, name.replace(/\.png$/, '.html'));
  writeFileSync(page, html);
  execFileSync(chrome, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
    `--window-size=${W},${H}`, `--screenshot=${join(out, name)}`, `file://${page}`], { stdio: 'ignore' });
  console.log(join(out, name));
}
