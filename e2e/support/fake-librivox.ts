import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

/**
 * A local stand-in for https://librivox.org/api/feed. The app's DEBUG build reads it from
 * `-e2e-librivox-feed <url>` (only together with `-e2e-fixture`). The simulator shares the
 * host's loopback, and ATS `NSAllowsArbitraryLoads` permits plain http to 127.0.0.1, so
 * both foreground requests and the background URLSession reach this server.
 *
 * Responses keep the real feed's shapes: `{"books":[...]}`, `{"sections":[...]}`, and the
 * HTTP 404 `{"error":"Audiobooks could not be found"}` no-match sentinel.
 */

export interface FakeBook {
  id: string;
  title: string;
  first: string;
  last: string;
  language: string;
  seconds: number;
  genre: string;
  tracks: number;
}

// Mirrors Pageless/App/E2EFixtures.swift `catalogRows`, so online and offline runs agree.
// Every book has two chapters.
export const fakeCatalog: FakeBook[] = [
  { id: '253', title: 'Pride and Prejudice', first: 'Jane', last: 'Austen', language: 'English', seconds: 47204, genre: 'General Fiction', tracks: 2 },
  { id: '314', title: 'Adventures of Sherlock Holmes', first: 'Arthur Conan', last: 'Doyle', language: 'English', seconds: 37800, genre: 'Detective Fiction', tracks: 2 },
  { id: '133', title: 'Jane Eyre', first: 'Charlotte', last: 'Brontë', language: 'English', seconds: 68400, genre: 'Romance', tracks: 2 },
  { id: '449', title: 'Treasure Island', first: 'Robert Louis', last: 'Stevenson', language: 'English', seconds: 25200, genre: 'Action & Adventure Fiction', tracks: 2 },
  { id: '381', title: 'Frankenstein, or The Modern Prometheus', first: 'Mary', last: 'Shelley', language: 'English', seconds: 30600, genre: 'Horror & Supernatural Fiction', tracks: 2 },
  { id: '271', title: 'Dracula', first: 'Bram', last: 'Stoker', language: 'English', seconds: 55800, genre: 'Horror & Supernatural Fiction', tracks: 2 },
  { id: '436', title: 'War of the Worlds', first: 'H. G.', last: 'Wells', language: 'English', seconds: 22800, genre: 'Science Fiction', tracks: 2 },
  { id: '510', title: 'Tale of Two Cities', first: 'Charles', last: 'Dickens', language: 'English', seconds: 57600, genre: 'Historical Fiction', tracks: 2 },
  { id: '661', title: 'Persuasion', first: 'Jane', last: 'Austen', language: 'English', seconds: 30000, genre: 'Romance', tracks: 2 },
  { id: '620', title: 'Sense and Sensibility', first: 'Jane', last: 'Austen', language: 'English', seconds: 42000, genre: 'Romance', tracks: 2 },
  { id: '86', title: 'Emma', first: 'Jane', last: 'Austen', language: 'English', seconds: 57000, genre: 'Romance', tracks: 2 },
  { id: '911', title: 'Wuthering Heights', first: 'Emily', last: 'Brontë', language: 'English', seconds: 44000, genre: 'Romance', tracks: 2 },
  { id: '2531', title: 'Pride and Prejudice (version 2)', first: 'Jane', last: 'Austen', language: 'English', seconds: 45000, genre: 'General Fiction', tracks: 2 },
  { id: '1203', title: 'Die Verwandlung', first: 'Franz', last: 'Kafka', language: 'German', seconds: 7200, genre: 'Short Stories', tracks: 2 },
];

export interface FakeLibriVox {
  /** Base feed URL to pass after `-e2e-librivox-feed`. */
  feedURL: string;
  /** Every request path (with query) in arrival order. */
  requests: string[];
  /** The next `times` requests for any audio file of `projectID` answer `status`. */
  failAudio(projectID: string, times: number, status?: number): void;
  /** The next `times` title or author searches answer an HTML 500, like a feed outage. */
  failSearch(times: number): void;
  audioRequests(projectID: string): string[];
  close(): Promise<void>;
}

/** 8 kHz mono PCM silence: small, but real audio AVPlayer can play. */
function silenceWAV(seconds: number): Buffer {
  const samples = seconds * 8_000;
  const dataBytes = samples * 2;
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(dataBytes + 36, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(8_000, 24); header.writeUInt32LE(16_000, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(dataBytes, 40);
  return Buffer.concat([header, Buffer.alloc(dataBytes)]);
}

export interface FakeLibriVoxOptions {
  port?: number;
  /**
   * Length of every chapter. The default 4 seconds keeps downloads fast. The 20-second sample
   * starts 30 seconds in, so sample tests need longer chapters.
   */
  trackSeconds?: number;
  /** Delay before each audio response starts, which holds a download in progress. */
  audioDelayMs?: number;
}

function playtime(seconds: number): string {
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${pad(Math.floor(seconds / 60))}:${pad(seconds % 60)}`;
}

function bookJSON(book: FakeBook) {
  return {
    id: book.id,
    title: book.title,
    description: `${book.title}, served by the e2e fake feed.`,
    totaltimesecs: book.seconds,
    authors: [{ first_name: book.first, last_name: book.last }],
    language: book.language,
    url_librivox: `https://librivox.org/e2e-${book.id}/`,
    genres: [{ id: '1', name: book.genre }],
  };
}

/** Serves `bytes` honoring a single `Range: bytes=a-b` header. AVPlayer streams with ranges. */
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

function json(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

export async function startFakeLibriVox(options: FakeLibriVoxOptions = {}): Promise<FakeLibriVox> {
  const { port = 47253, trackSeconds = 4, audioDelayMs = 0 } = options;
  const audio = silenceWAV(trackSeconds);
  const requests: string[] = [];
  const failures = new Map<string, { remaining: number; status: number }>();
  let searchFailures = 0;
  let base = '';

  const handle = async (req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? '/', base);
    requests.push(url.pathname + url.search);
    const params = url.searchParams;

    if (url.pathname === '/api/feed/audiobooks') {
      if (searchFailures > 0 && (params.has('title') || params.has('author'))) {
        searchFailures -= 1;
        res.writeHead(500, { 'content-type': 'text/html' });
        return res.end('<html><body>e2e injected outage</body></html>');
      }
      let books = fakeCatalog;
      const id = params.get('id');
      const title = params.get('title')?.toLowerCase();
      const author = params.get('author')?.toLowerCase();
      if (id) books = books.filter((book) => book.id === id);
      if (title) books = books.filter((book) => book.title.toLowerCase().includes(title));
      if (author) books = books.filter((book) => `${book.first} ${book.last}`.toLowerCase().includes(author));
      if (params.has('since')) books = [];
      const offset = Number(params.get('offset') ?? 0);
      const limit = Number(params.get('limit') ?? 50);
      books = books.slice(offset, offset + limit);
      if (books.length === 0) return json(res, 404, { error: 'Audiobooks could not be found' });
      return json(res, 200, { books: books.map(bookJSON) });
    }

    if (url.pathname === '/api/feed/audiotracks') {
      const book = fakeCatalog.find((entry) => entry.id === params.get('project_id'));
      if (!book) return json(res, 404, { error: 'Audiotracks could not be found' });
      const sections = Array.from({ length: book.tracks }, (_, index) => ({
        id: `${book.id}${index + 1}`,
        section_number: String(index + 1),
        title: `Chapter ${index + 1}`,
        playtime: playtime(trackSeconds),
        listen_url: `${base}/audio/${book.id}/${index + 1}.wav`,
      }));
      return json(res, 200, { sections });
    }

    const audioMatch = /^\/audio\/([^/]+)\/\d+\.wav$/.exec(url.pathname);
    if (audioMatch) {
      const failure = failures.get(audioMatch[1]);
      if (failure && failure.remaining > 0) {
        failure.remaining -= 1;
        res.writeHead(failure.status, { 'content-type': 'text/html' });
        return res.end('<html><body>e2e injected failure</body></html>');
      }
      if (audioDelayMs > 0) await delay(audioDelayMs);
      if (res.destroyed) return;
      return sendAudio(req, res, audio);
    }

    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('not found');
  };

  const server: Server = createServer((req, res) => {
    handle(req, res).catch(() => res.destroy());
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

  return {
    feedURL: `${base}/api/feed`,
    requests,
    failAudio(projectID, times, status = 500) {
      failures.set(projectID, { remaining: times, status });
    },
    failSearch(times) {
      searchFailures = times;
    },
    audioRequests(projectID) {
      return requests.filter((path) => path.startsWith(`/audio/${projectID}/`));
    },
    close: () => new Promise<void>((resolve) => {
      server.closeAllConnections();
      server.close(() => resolve());
    }),
  };
}
