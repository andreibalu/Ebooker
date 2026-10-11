import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

/**
 * A local Audiobookshelf server for the Shelves → Audiobookshelf flows. The app reaches it at
 * http://127.0.0.1:<port>; loopback counts as a private host, so no plain-http warning appears.
 *
 * Responses follow the shapes AudiobookshelfClient decodes (verified against ABS 2.36.1 in the
 * unit tests): `/login` returns `user.accessToken`/`refreshToken`, expanded items list their
 * files under `media.tracks`, a playback session lists them under `audioTracks`, and audio
 * accepts the `?token=` query AVPlayer has to use because it cannot send headers.
 */

export const ABS_USERNAME = 'e2e-reader';
export const ABS_PASSWORD = 'e2e-password';
export const ABS_API_KEY = 'e2e-api-key';
const ACCESS_TOKEN = 'e2e-access-token';
const REFRESH_TOKEN = 'e2e-refresh-token';

interface FakeItem {
  id: string;
  libraryId: string;
  title: string;
  author: string;
  narrator: string;
  addedAt: number;
  tracks: number;
  /** Server-side listening position in seconds, if the person already started the book. */
  progress?: number;
  trackSeconds?: number;
  sequence?: string;
  finished?: boolean;
}

export const TRACK_SECONDS = 30;

export const absItems: FakeItem[] = [
  { id: 'abs-hobbit', libraryId: 'lib-main', title: 'The Fixture Hobbit', author: 'E2E Tolkien', narrator: 'E2E Narrator', addedAt: 1_700_000_000_000, tracks: 2 },
  { id: 'abs-dune', libraryId: 'lib-main', title: 'Dune of Fixtures', author: 'E2E Herbert', narrator: '', addedAt: 1_700_000_100_000, tracks: 1, progress: 12 },
  { id: 'abs-poems', libraryId: 'lib-poetry', title: 'Collected Test Poems', author: 'E2E Dickinson', narrator: '', addedAt: 1_700_000_200_000, tracks: 1 },
];

absItems.push(...[
  { id: 'abs-series-ten', title: 'Volume Ten', sequence: '10', finished: true, progress: 30 },
  { id: 'abs-series-two', title: 'Volume Two', sequence: '2', author: 'E2E Herbert', narrator: 'E2E Other Narrator' },
  { id: 'abs-series-none', title: 'Unnumbered Tale' },
  { id: 'abs-series-half', title: 'Volume Interlude', sequence: '1.5' },
  { id: 'abs-series-one', title: 'Volume One', sequence: '1' },
].map((entry) => ({ libraryId: 'lib-main', author: 'E2E Tolkien', narrator: 'E2E Narrator',
  addedAt: 1_700_000_300_000, tracks: 1, ...entry })));

const authorID = (item: FakeItem) => `author-${item.author.replaceAll(' ', '-')}`;

const libraries = [
  { id: 'lib-main', name: 'E2E Shelf', mediaType: 'book' },
  { id: 'lib-poetry', name: 'Poetry Shelf', mediaType: 'book' },
  { id: 'lib-podcasts', name: 'Podcasts', mediaType: 'podcast' },
];

export interface ProgressPatch { itemID: string; currentTime: number; duration: number; isFinished: boolean }

export interface FakeAudiobookshelf {
  /** What a person types into the Server field. */
  serverURL: string;
  /** Every request as `METHOD path?query`, in arrival order. */
  requests: string[];
  progressPatches: ProgressPatch[];
  /** Audio requests for `itemID`, with the `token` query value each one carried. */
  audioTokens(itemID: string): (string | null)[];
  setProgress(itemID: string, currentTime: number, lastUpdate?: number, isFinished?: boolean): void;
  setProgressFailure(mode: 500 | 'unreachable' | null): void;
  audioDelayMS: number;
  close(): Promise<void>;
}

function silenceWAV(seconds: number): Buffer {
  const dataBytes = seconds * 8_000 * 2;
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(dataBytes + 36, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(8_000, 24); header.writeUInt32LE(16_000, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(dataBytes, 40);
  return Buffer.concat([header, Buffer.alloc(dataBytes)]);
}

const audio = silenceWAV(TRACK_SECONDS);

function track(item: FakeItem, index: number) {
  return {
    index: index + 1,
    startOffset: index * (item.trackSeconds ?? TRACK_SECONDS),
    duration: item.trackSeconds ?? TRACK_SECONDS,
    title: `part-${index + 1}.wav`,
    contentUrl: `/audio/${item.id}/${index + 1}.wav`,
    mimeType: 'audio/wav',
    metaTags: { tagTitle: `${item.title} Part ${index + 1}` },
  };
}

function itemJSON(item: FakeItem, expanded: boolean) {
  const tracks = Array.from({ length: item.tracks }, (_, index) => track(item, index));
  return {
    id: item.id,
    libraryId: item.libraryId,
    mediaType: 'book',
    addedAt: item.addedAt,
    media: {
      metadata: {
        title: item.title,
        authors: [{ id: authorID(item), name: item.author }],
        narrators: item.narrator ? [item.narrator] : [],
        ...(expanded ? { authorName: item.author, narratorName: item.narrator } : {}),
        description: `<p>${item.title} is served by the e2e fake Audiobookshelf server.</p>`,
      },
      duration: item.tracks * (item.trackSeconds ?? TRACK_SECONDS),
      numTracks: item.tracks,
      coverPath: '',
      ...(expanded ? { tracks, audioTracks: null, chapters: [] } : {}),
    },
  };
}

function progressJSON(item: FakeItem, currentTime: number) {
  const duration = item.tracks * (item.trackSeconds ?? TRACK_SECONDS);
  return {
    libraryItemId: item.id, duration, currentTime,
    progress: duration > 0 ? currentTime / duration : 0,
    isFinished: item.finished ?? false, lastUpdate: Date.now(),
  };
}

function json(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

async function readBody(req: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks).toString('utf8');
}

/** Serves `bytes` honoring a single `Range: bytes=a-b` header, which AVPlayer streaming uses. */
function sendAudio(req: IncomingMessage, res: ServerResponse, bytes: Buffer) {
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
  if (!range) {
    res.writeHead(200, { 'content-type': 'audio/wav', 'content-length': bytes.length, 'accept-ranges': 'bytes' });
    return res.end(req.method === 'HEAD' ? undefined : bytes);
  }
  const start = range[1] ? Number(range[1]) : Math.max(0, bytes.length - Number(range[2]));
  const end = range[1] && range[2] ? Math.min(Number(range[2]), bytes.length - 1) : bytes.length - 1;
  res.writeHead(206, {
    'content-type': 'audio/wav', 'accept-ranges': 'bytes',
    'content-range': `bytes ${start}-${end}/${bytes.length}`, 'content-length': end - start + 1,
  });
  res.end(req.method === 'HEAD' ? undefined : bytes.subarray(start, end + 1));
}

export async function startFakeAudiobookshelf(port = 47378, longBook = false): Promise<FakeAudiobookshelf> {
  if (longBook) absItems[0].trackSeconds = 360;
  else delete absItems[0].trackSeconds;
  const requests: string[] = [];
  const progressPatches: ProgressPatch[] = [];
  const audioTokenLog: { itemID: string; token: string | null }[] = [];
  const progress = new Map(absItems.filter((item) => item.progress).map((item) => [item.id, item.progress!]));
  const updates = new Map<string, { lastUpdate: number; isFinished: boolean }>();
  let progressFailure: 500 | 'unreachable' | null = null;
  const serverProgress = (item: FakeItem) => ({ ...progressJSON(item, progress.get(item.id)!),
    ...(updates.get(item.id) ?? { lastUpdate: 1_700_000_000_000, isFinished: item.finished ?? false }) });
  let base = '';
  const controls = { audioDelayMS: 0 };

  const authorized = (req: IncomingMessage) => {
    const header = req.headers.authorization ?? '';
    return header === `Bearer ${ACCESS_TOKEN}` || header === `Bearer ${ABS_API_KEY}`;
  };

  const handle = async (req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? '/', base);
    requests.push(`${req.method} ${url.pathname}${url.search}`);
    const path = url.pathname;

    if (path === '/login' && req.method === 'POST') {
      const body = JSON.parse((await readBody(req)) || '{}');
      if (body.username !== ABS_USERNAME || body.password !== ABS_PASSWORD) {
        res.writeHead(401, { 'content-type': 'text/plain' });
        return res.end('Unauthorized');
      }
      return json(res, 200, { user: { username: ABS_USERNAME, accessToken: ACCESS_TOKEN, refreshToken: REFRESH_TOKEN } });
    }

    const audioMatch = /^\/audio\/([^/]+)\/(\d+)\.wav$/.exec(path);
    if (audioMatch) {
      const token = url.searchParams.get('token');
      audioTokenLog.push({ itemID: audioMatch[1], token });
      if (token !== ACCESS_TOKEN && token !== ABS_API_KEY) {
        res.writeHead(401, { 'content-type': 'text/plain' });
        return res.end('Unauthorized');
      }
      const item = absItems.find((entry) => entry.id === audioMatch[1]);
      const body = item?.trackSeconds ? silenceWAV(item.trackSeconds) : audio;
      if (controls.audioDelayMS > 0) {
        res.writeHead(200, { 'content-type': 'audio/wav', 'content-length': body.length });
        res.write(body.subarray(0, 44_000));
        const timer = setTimeout(() => res.end(body.subarray(44_000)), controls.audioDelayMS);
        res.on('close', () => clearTimeout(timer));
        return;
      }
      return sendAudio(req, res, body);
    }

    if (!path.startsWith('/api/')) {
      res.writeHead(404, { 'content-type': 'text/plain' });
      return res.end('not found');
    }
    if (!authorized(req)) {
      res.writeHead(401, { 'content-type': 'text/plain' });
      return res.end('Unauthorized');
    }

    if (path === '/api/authorize' && req.method === 'POST') {
      return json(res, 200, { user: { username: 'e2e-key-owner' } });
    }
    if (path === '/api/libraries') return json(res, 200, { libraries });

    const groupMatch = /^\/api\/libraries\/([^/]+)\/(series|collections)$/.exec(path);
    if (groupMatch) {
      const page = Number(url.searchParams.get('page') ?? 0);
      const limit = Number(url.searchParams.get('limit') ?? 50);
      const groups = groupMatch[1] === 'lib-main' ? groupMatch[2] === 'series'
        ? [{ id: 'series-fixture', name: 'Fixture Saga', books: absItems.filter((item) => item.id.startsWith('abs-series-'))
          .map((item) => ({ ...itemJSON(item, true), sequence: item.sequence ?? null })) },
          ...Array.from({ length: 50 }, (_, index) => ({ id: `series-empty-${index}`, name: `Unused Saga ${index}`, books: [] }))]
        : [{ id: 'collection-fixture', name: 'Fixture Favorites', books: ['abs-dune', 'abs-hobbit']
          .map((id) => itemJSON(absItems.find((item) => item.id === id)!, true)) }] : [];
      return json(res, 200, { results: groups.slice(page * limit, (page + 1) * limit), total: groups.length, limit, page });
    }

    const itemsMatch = /^\/api\/libraries\/([^/]+)\/items$/.exec(path);
    if (itemsMatch) {
      const page = Number(url.searchParams.get('page') ?? 0);
      const limit = Number(url.searchParams.get('limit') ?? 50);
      let all = absItems.filter((item) => item.libraryId === itemsMatch[1]);
      const filter = url.searchParams.get('filter');
      if (filter) {
        const split = filter.indexOf('.');
        const kind = filter.slice(0, split);
        const value = Buffer.from(filter.slice(split + 1), 'base64').toString('utf8');
        if (kind === 'authors') all = all.filter((item) => authorID(item) === value);
        else if (kind === 'narrators') all = all.filter((item) => item.narrator === value);
        else return json(res, 400, { error: 'Unsupported filter' });
      }
      const results = all.slice(page * limit, page * limit + limit).map((item) => itemJSON(item, false));
      return json(res, 200, { results, total: all.length, limit, page });
    }

    if (path === '/api/me/progress' && req.method === 'GET') {
      const mediaProgress = absItems.filter((item) => progress.has(item.id))
        .map((item) => serverProgress(item));
      return json(res, 200, { mediaProgress });
    }

    const progressMatch = /^\/api\/me\/progress\/([^/]+)$/.exec(path);
    if (progressMatch) {
      const item = absItems.find((entry) => entry.id === progressMatch[1]);
      if (!item) return json(res, 404, {});
      if (req.method === 'PATCH') {
        if (progressFailure === 'unreachable') { req.socket.destroy(); return; }
        if (progressFailure === 500) return json(res, 500, {});
        const body = JSON.parse((await readBody(req)) || '{}');
        progressPatches.push({ itemID: item.id, currentTime: body.currentTime, duration: body.duration, isFinished: body.isFinished });
        progress.set(item.id, body.currentTime);
        updates.set(item.id, { lastUpdate: Date.now(), isFinished: body.isFinished });
        return json(res, 200, {});
      }
      if (!progress.has(item.id)) return json(res, 404, {});
      return json(res, 200, serverProgress(item));
    }

    const playMatch = /^\/api\/items\/([^/]+)\/play$/.exec(path);
    if (playMatch && req.method === 'POST') {
      const item = absItems.find((entry) => entry.id === playMatch[1]);
      if (!item) return json(res, 404, {});
      return json(res, 200, {
        id: `session-${item.id}`, libraryItemId: item.id,
        audioTracks: Array.from({ length: item.tracks }, (_, index) => track(item, index)),
        chapters: [], currentTime: progress.get(item.id) ?? 0,
      });
    }

    const itemMatch = /^\/api\/items\/([^/]+)$/.exec(path);
    if (itemMatch) {
      const item = absItems.find((entry) => entry.id === itemMatch[1]);
      if (!item) return json(res, 404, {});
      return json(res, 200, itemJSON(item, true));
    }

    json(res, 404, {});
  };

  const server: Server = createServer((req, res) => {
    handle(req, res).catch((error) => {
      res.writeHead(500, { 'content-type': 'text/plain' });
      res.end(String(error));
    });
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

  return {
    get audioDelayMS() { return controls.audioDelayMS; },
    set audioDelayMS(value: number) { controls.audioDelayMS = value; },
    serverURL: base,
    requests,
    progressPatches,
    setProgress: (itemID, currentTime, lastUpdate = Date.now(), isFinished = false) => {
      progress.set(itemID, currentTime); updates.set(itemID, { lastUpdate, isFinished });
    },
    setProgressFailure: (mode) => { progressFailure = mode; },
    audioTokens: (itemID) => audioTokenLog.filter((entry) => entry.itemID === itemID).map((entry) => entry.token),
    close: () => new Promise<void>((resolve) => {
      server.closeAllConnections();
      server.close(() => resolve());
    }),
  };
}
