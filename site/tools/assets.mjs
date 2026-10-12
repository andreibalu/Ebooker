#!/usr/bin/env node
// Regenerates the committed images in public/ from the App Store screenshots and the app icon.
// Run after the screenshots or the icon change:  npm install && npm run assets
// The site build itself (build.mjs) has no dependencies and only copies these files.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.resolve(here, '..');
const repo = path.resolve(site, '..');
const pub = path.join(site, 'public');
const shots = path.join(repo, 'screenshots/public/screenshots/en');
const iconPng = path.join(repo, 'Pageless/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png');
fs.mkdirSync(path.join(pub, 'screens'), { recursive: true });
fs.mkdirSync(path.join(pub, 'img'), { recursive: true });

const screens = {
  library: '02-library.png', librivox: '01-shelves-librivox.png', abs: '05-shelves-audiobookshelf.png',
  player: '03-player.png', eq: '06-essentials-eq.png', moments: '04-moments.png',
  stats: 'reading-stats.png', recap: 'recap.png'
};
const W = 720, H = 1564;

// Device captures carry a real status bar (time, mute, battery). Repaint it as the simulator's clean 9:41.
async function cleanStatusBar(file) {
  const img = sharp(file);
  const { width } = await img.metadata();
  if (width === 1320) return img;
  const { data } = await sharp(file).extract({ left: 40, top: 20, width: 1, height: 1 }).raw().toBuffer({ resolveWithObject: true });
  const bg = `rgb(${data[0]},${data[1]},${data[2]})`;
  const ink = data[0] + data[1] + data[2] > 380 ? '#000' : '#fff';
  const s = width / 393;
  const bar = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${Math.round(54 * s)}">
    <rect width="100%" height="100%" fill="${bg}"/>
    <text x="${Math.round(51 * s)}" y="${Math.round(36 * s)}" font-family="-apple-system, Helvetica Neue, Helvetica" font-weight="600" font-size="${Math.round(17 * s)}" text-anchor="middle" fill="${ink}">9:41</text>
    <g transform="translate(${Math.round(294 * s)} ${Math.round(23 * s)}) scale(${s})" fill="${ink}">
      <rect x="0" y="8" width="3" height="4" rx="1"/><rect x="4.5" y="6" width="3" height="6" rx="1"/><rect x="9" y="3.5" width="3" height="8.5" rx="1"/><rect x="13.5" y="1" width="3" height="11" rx="1"/>
      <path d="M28 3.2a9.6 9.6 0 0 1 6.8 2.8l1.2-1.2a11.3 11.3 0 0 0-16 0l1.2 1.2A9.6 9.6 0 0 1 28 3.2Zm0 3.4a6.2 6.2 0 0 1 4.4 1.8l1.2-1.2a7.9 7.9 0 0 0-11.2 0l1.2 1.2A6.2 6.2 0 0 1 28 6.6Zm0 3.4a2.8 2.8 0 0 1 2 .8L28 12.8l-2-2a2.8 2.8 0 0 1 2-.8Z"/>
      <rect x="42" y="0.5" width="24" height="12" rx="3.5" fill="none" stroke="${ink}" stroke-opacity=".4"/><rect x="44" y="2.5" width="20" height="8" rx="2"/><rect x="67.5" y="4.5" width="1.6" height="4" rx=".8" fill-opacity=".45"/>
    </g></svg>`;
  return sharp(await img.composite([{ input: Buffer.from(bar), top: 0, left: 0 }]).png().toBuffer());
}

await Promise.all(Object.entries(screens).map(async ([name, file]) => {
  const img = await cleanStatusBar(path.join(shots, file));
  await img.resize({ width: W, height: H, fit: 'cover', position: 'top' }).webp({ quality: 86 }).toFile(path.join(pub, `screens/${name}.webp`));
}));
await sharp(iconPng).resize(512).webp({ quality: 92 }).toFile(path.join(pub, 'img/icon-512.webp'));
await sharp(iconPng).resize(180).png().toFile(path.join(pub, 'img/apple-touch-icon.png'));

// Open Graph card: cream field, the icon, the line, the library screen.
const iconB64 = (await sharp(iconPng).resize(132).png().toBuffer()).toString('base64');
const shotB64 = (await sharp(path.join(pub, 'screens/library.webp')).resize(300).png().toBuffer()).toString('base64');
const og = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630"><rect width="1200" height="630" fill="#f7f3ed"/>
<rect x="760" y="0" width="440" height="630" fill="#122231"/><rect x="842" y="-40" width="64" height="300" fill="#f4efe8"/><circle cx="874" cy="300" r="20" fill="#e49a21"/>
<g transform="translate(830 70) rotate(4)"><rect x="-8" y="-8" width="316" height="668" rx="52" fill="#0b1520"/><image href="data:image/png;base64,${shotB64}" width="300" height="652" clip-path="inset(0 round 44px)"/></g>
<image href="data:image/png;base64,${iconB64}" x="80" y="78" width="88" height="88"/>
<text x="186" y="136" font-family="Georgia, serif" font-size="44" fill="#15202b">Unpaged</text>
<text x="80" y="300" font-family="Georgia, serif" font-size="76" fill="#15202b">Listen to the book.</text>
<text x="80" y="390" font-family="Georgia, serif" font-size="76" fill="#15202b">Keep the <tspan font-style="italic" fill="#b8742a">moments.</tspan></text>
<text x="82" y="520" font-family="Helvetica, Arial" font-size="26" fill="#5e5a52">Audiobook player for iPhone · Free on the App Store</text></svg>`;
await sharp(Buffer.from(og)).png().toFile(path.join(pub, 'img/og.png'));

// Self-hosted Newsreader (OFL), from @fontsource-variable/newsreader.
const fonts = path.join(site, 'node_modules/@fontsource-variable/newsreader/files');
if (fs.existsSync(fonts)) {
  fs.mkdirSync(path.join(pub, 'fonts'), { recursive: true });
  fs.copyFileSync(path.join(fonts, 'newsreader-latin-opsz-normal.woff2'), path.join(pub, 'fonts/newsreader.woff2'));
  fs.copyFileSync(path.join(fonts, 'newsreader-latin-opsz-italic.woff2'), path.join(pub, 'fonts/newsreader-italic.woff2'));
}
console.log('Images written to public/');
