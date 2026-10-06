import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

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
export const fakeCatalog: FakeBook[] = [
  { id: '253', title: 'Pride and Prejudice', first: 'Jane', last: 'Austen', language: 'English', seconds: 47204, genre: 'General Fiction', tracks: 2 },
  { id: '314', title: 'Adventures of Sherlock Holmes', first: 'Arthur Conan', last: 'Doyle', language: 'English', seconds: 37800, genre: 'Detective Fiction', tracks: 2 },
  { id: '133', title: 'Jane Eyre', first: 'Charlotte', last: 'Brontë', language: 'English', seconds: 68400, genre: 'Romance', tracks: 2 },
  { id: '449', title: 'Treasure Island', first: 'Robert Louis', last: 'Stevenson', language: 'English', seconds: 25200, genre: 'Action & Adventure Fiction', tracks: 2 },
  { id: '2531', title: 'Pride and Prejudice (version 2)', first: 'Jane', last: 'Austen', language: 'English', seconds: 45000, genre: 'General Fiction', tracks: 2 },
];

export interface FakeLibriVox {
  /** Base feed URL to pass after `-e2e-librivox-feed`. */
  feedURL: string;
  /** Every request path (with query) in arrival order. */
  requests: string[];
  /** The next `times` requests for any audio file of `projectID` answer `status`. */
  failAudio(projectID: string, times: number, status?: number): void;
  audioRequests(projectID: string): string[];
  close(): Promise<void>;
}

/** Four seconds of 8 kHz mono PCM silence: tiny, but real audio AVPlayer can play. */
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

const TRACK_SECONDS = 4;
const audio = silenceWAV(TRACK_SECONDS);

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

function json(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

export async function startFakeLibriVox(port = 47253): Promise<FakeLibriVox> {
  const requests: string[] = [];
  const failures = new Map<string, { remaining: number; status: number }>();
  let base = '';

  const handle = (req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? '/', base);
    requests.push(url.pathname + url.search);
    const params = url.searchParams;

    if (url.pathname === '/api/feed/audiobooks') {
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
        playtime: `00:0${TRACK_SECONDS}`,
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
      res.writeHead(200, { 'content-type': 'audio/wav', 'content-length': audio.length });
      return res.end(audio);
    }

    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('not found');
  };

  const server: Server = createServer(handle);
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
    audioRequests(projectID) {
      return requests.filter((path) => path.startsWith(`/audio/${projectID}/`));
    },
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}
