// Renders one typographic cover per demo book with headless Chrome (no third-party artwork).
//   node screenshots/abs-demo/covers.mjs <out-dir>
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { books } from './books.mjs';

const out = process.argv[2] ?? 'covers';
mkdirSync(out, { recursive: true });
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const styles = ['band', 'frame', 'rule'];

books.forEach((book, i) => {
  const [bg, fg] = book.palette;
  const style = styles[i % styles.length];
  const html = `<!doctype html><html><head><style>
    html,body{margin:0;width:800px;height:800px;overflow:hidden}
    body{background:${bg};color:${fg};font-family:"Baskerville","Georgia",serif;display:flex}
    .c{position:relative;flex:1;margin:${style === 'frame' ? 44 : 0}px;padding:70px 64px;box-sizing:border-box;
       ${style === 'frame' ? `border:3px solid ${fg};` : ''}display:flex;flex-direction:column;justify-content:${style === 'band' ? 'flex-end' : 'center'}}
    .band{position:absolute;left:0;right:0;top:0;height:300px;background:${fg};opacity:.92}
    .t{font-size:${book.title.length > 24 ? 70 : 88}px;line-height:1.02;font-weight:600;letter-spacing:-.5px}
    .r{width:120px;height:4px;background:${fg};margin:40px 0 34px}
    .a{font-family:-apple-system,"Helvetica Neue",sans-serif;font-size:30px;letter-spacing:6px;text-transform:uppercase;opacity:.85}
    .s{font-family:-apple-system,"Helvetica Neue",sans-serif;font-size:24px;letter-spacing:4px;text-transform:uppercase;opacity:.7;margin-bottom:26px}
  </style></head><body><div class="c">${style === 'band' ? '<div class="band"></div>' : ''}
    ${book.series ? `<div class="s">${book.series} · ${book.sequence}</div>` : ''}
    <div class="t">${book.title}</div><div class="r"></div><div class="a">${book.author}</div>
  </div></body></html>`;
  const page = join(out, `${book.id}.html`);
  writeFileSync(page, html);
  execFileSync(chrome, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
    '--window-size=800,800', `--screenshot=${join(out, `${book.id}.png`)}`, `file://${page}`], { stdio: 'ignore' });
});
console.log(`Rendered ${books.length} covers into ${out}`);
