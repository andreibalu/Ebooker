// A demo Audiobookshelf server for the custom product page captures, modeled on
// e2e/support/fake-audiobookshelf.ts (same login, routes and response shapes) but with a
// presentable public-domain library, cover art and chapter-length silent audio.
//
//   node screenshots/abs-demo/server.mjs <covers-dir> [port]
//   curl 'http://127.0.0.1:47379/__throttle?kbps=200'   # slow audio, to catch a download mid-way
//
// Sign in with demo / demo-password.
import { createServer } from 'node:http';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { books } from './books.mjs';

const coversDir = process.argv[2] ?? 'covers';
const port = Number(process.argv[3] ?? 47379);
const USER = 'demo', PASSWORD = 'demo-password', ACCESS = 'demo-access-token', REFRESH = 'demo-refresh-token';
const houndChapters = ['Mr. Sherlock Holmes', 'The Curse of the Baskervilles', 'The Problem', 'Sir Henry Baskerville',
  'Three Broken Threads', 'Baskerville Hall', 'The Stapletons of Merripit House', 'First Report of Dr. Watson',
  'The Light upon the Moor', 'Extract from the Diary of Dr. Watson', 'The Man on the Tor', 'Death on the Moor',
  'Fixing the Nets', 'The Hound of the Baskervilles', 'A Retrospection'];
const library = { id: 'lib-books', name: 'Audiobooks', mediaType: 'book' };
const collections = [
  { id: 'col-gothic', name: 'Gothic Nights', ids: ['dracula', 'frankenstein', 'eyre'] },
  { id: 'col-long', name: 'Long Winter Reads', ids: ['monte', 'moby', 'expectations', 'women'] },
];
let throttleKBps = 0;

const trackSeconds = (b) => Math.round((b.minutes * 60) / b.chapters);
const duration = (b) => trackSeconds(b) * b.chapters;
const chapterTitle = (b, i) => (b.id === 'hound' ? houndChapters[i] : `Chapter ${i + 1}`);
const progress = new Map(books.filter((b) => b.progress || b.finished)
  .map((b) => [b.id, { currentTime: b.finished ? duration(b) : Math.round(duration(b) * b.progress), isFinished: !!b.finished }]));

function tracks(b) {
  const s = trackSeconds(b);
  return Array.from({ length: b.chapters }, (_, i) => ({
    index: i + 1, startOffset: i * s, duration: s, title: `${String(i + 1).padStart(2, '0')}.wav`,
    contentUrl: `/audio/${b.id}/${i + 1}.wav`, mimeType: 'audio/wav', metaTags: { tagTitle: chapterTitle(b, i) },
  }));
}
const chapters = (b) => tracks(b).map((t, i) => ({ id: i, start: t.startOffset, end: t.startOffset + t.duration, title: chapterTitle(b, i) }));

function item(b, expanded) {
  return {
    id: b.id, libraryId: library.id, mediaType: 'book', addedAt: 1_760_000_000_000 - books.indexOf(b) * 86_400_000,
    ...(b.sequence ? { sequence: b.sequence } : {}),
    media: {
      metadata: {
        title: b.title, authors: [{ id: `author-${b.author.replace(/\W+/g, '-')}`, name: b.author }], narrators: [],
        ...(expanded ? { authorName: b.author, narratorName: '' } : {}),
        description: `<p>${b.blurb ?? `${b.title} by ${b.author}.`}</p>`,
      },
      duration: duration(b), numTracks: b.chapters, numChapters: b.chapters, coverPath: `/metadata/items/${b.id}/cover.png`,
      ...(expanded ? { tracks: tracks(b), audioTracks: null, chapters: chapters(b) } : {}),
    },
  };
}
const progressJSON = (b) => {
  const p = progress.get(b.id);
  return { libraryItemId: b.id, duration: duration(b), currentTime: p.currentTime, progress: p.isFinished ? 1 : p.currentTime / duration(b),
    isFinished: p.isFinished, lastUpdate: p.lastUpdate ?? 1_760_000_000_000 };
};

const wavCache = new Map();
function silence(seconds) {
  if (wavCache.has(seconds)) return wavCache.get(seconds);
  const data = seconds * 8_000 * 2, h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(data + 36, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22); h.writeUInt32LE(8_000, 24); h.writeUInt32LE(16_000, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(data, 40);
  const wav = Buffer.concat([h, Buffer.alloc(data)]);
  wavCache.set(seconds, wav);
  return wav;
}
function send(req, res, bytes) {
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
  let start = 0, end = bytes.length - 1, status = 200;
  const headers = { 'content-type': 'audio/wav', 'accept-ranges': 'bytes' };
  if (range) {
    start = range[1] ? Number(range[1]) : Math.max(0, bytes.length - Number(range[2]));
    end = range[1] && range[2] ? Math.min(Number(range[2]), bytes.length - 1) : bytes.length - 1;
    status = 206; headers['content-range'] = `bytes ${start}-${end}/${bytes.length}`;
  }
  headers['content-length'] = end - start + 1;
  res.writeHead(status, headers);
  if (req.method === 'HEAD') return res.end();
  const body = bytes.subarray(start, end + 1);
  if (!throttleKBps) return res.end(body);
  let offset = 0;
  const chunk = throttleKBps * 1024 / 10;
  const timer = setInterval(() => {
    if (offset >= body.length) { clearInterval(timer); return res.end(); }
    res.write(body.subarray(offset, offset + chunk)); offset += chunk;
  }, 100);
  res.on('close', () => clearInterval(timer));
}
const json = (res, status, body) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
const readBody = async (req) => { const c = []; for await (const x of req) c.push(x); return Buffer.concat(c).toString('utf8'); };
const authorized = (req, url) => [`Bearer ${ACCESS}`].includes(req.headers.authorization ?? '') || url.searchParams.get('token') === ACCESS;
const find = (id) => books.find((b) => b.id === id);
const page = (url, all) => {
  const p = Number(url.searchParams.get('page') ?? 0), limit = Number(url.searchParams.get('limit') ?? 50);
  return { results: all.slice(p * limit, (p + 1) * limit), total: all.length, limit, page: p };
};

createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://127.0.0.1:${port}`);
  const path = url.pathname;
  console.log(req.method, path + url.search.replace(/token=[^&]+/, 'token=…'));
  try {
    if (path === '/__throttle') { throttleKBps = Number(url.searchParams.get('kbps') ?? 0); return json(res, 200, { throttleKBps }); }
    if (path === '/login' && req.method === 'POST') {
      const body = JSON.parse((await readBody(req)) || '{}');
      if (body.username !== USER || body.password !== PASSWORD) { res.writeHead(401); return res.end('Unauthorized'); }
      return json(res, 200, { user: { username: USER, accessToken: ACCESS, refreshToken: REFRESH } });
    }
    if (path === '/auth/refresh' && req.method === 'POST') return json(res, 200, { user: { username: USER, accessToken: ACCESS, refreshToken: REFRESH } });
    if (!authorized(req, url)) { res.writeHead(401); return res.end('Unauthorized'); }
    const audio = /^\/audio\/([^/]+)\/(\d+)\.wav$/.exec(path);
    if (audio) return send(req, res, silence(trackSeconds(find(audio[1]))));
    const cover = /^\/api\/items\/([^/]+)\/cover$/.exec(path);
    if (cover) {
      const file = join(coversDir, `${cover[1]}.png`);
      if (!existsSync(file)) return json(res, 404, {});
      res.writeHead(200, { 'content-type': 'image/png' }); return res.end(readFileSync(file));
    }
    if (path === '/api/libraries') return json(res, 200, { libraries: [library] });
    const group = /^\/api\/libraries\/[^/]+\/(series|collections)$/.exec(path);
    if (group) {
      const groups = group[1] === 'series'
        ? [{ id: 'series-holmes', name: 'Sherlock Holmes', books: books.filter((b) => b.series).map((b) => ({ ...item(b, true), sequence: b.sequence })) }]
        : collections.map((c) => ({ id: c.id, name: c.name, books: c.ids.map((id) => item(find(id), true)) }));
      return json(res, 200, page(url, groups));
    }
    if (/^\/api\/libraries\/[^/]+\/items$/.test(path)) {
      let all = books;
      const filter = url.searchParams.get('filter');
      if (filter?.startsWith('authors.')) {
        const id = Buffer.from(filter.slice(8), 'base64').toString('utf8');
        all = books.filter((b) => `author-${b.author.replace(/\W+/g, '-')}` === id);
      }
      return json(res, 200, page(url, all.map((b) => item(b, false))));
    }
    if (path === '/api/me/progress') return json(res, 200, { mediaProgress: books.filter((b) => progress.has(b.id)).map(progressJSON) });
    const prog = /^\/api\/me\/progress\/([^/]+)$/.exec(path);
    if (prog) {
      const b = find(prog[1]);
      if (req.method === 'PATCH') {
        const body = JSON.parse((await readBody(req)) || '{}');
        progress.set(b.id, { currentTime: body.currentTime, isFinished: body.isFinished, lastUpdate: Date.now() });
        console.log(`  progress ${b.id} → ${Math.round(body.currentTime)} s`);
        return json(res, 200, {});
      }
      return progress.has(b.id) ? json(res, 200, progressJSON(b)) : json(res, 404, {});
    }
    const play = /^\/api\/items\/([^/]+)\/play$/.exec(path);
    if (play) {
      const b = find(play[1]);
      return json(res, 200, { id: `session-${b.id}`, libraryItemId: b.id, audioTracks: tracks(b), chapters: chapters(b), currentTime: progress.get(b.id)?.currentTime ?? 0 });
    }
    const one = /^\/api\/items\/([^/]+)$/.exec(path);
    if (one && find(one[1])) return json(res, 200, item(find(one[1]), true));
    json(res, 404, {});
  } catch (error) { res.writeHead(500); res.end(String(error)); }
}).listen(port, '127.0.0.1', () => console.log(`Demo Audiobookshelf on http://127.0.0.1:${port}`));
