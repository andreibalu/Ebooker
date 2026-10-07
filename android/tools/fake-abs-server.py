#!/usr/bin/env python3
"""Deterministic ABS contract fixture. Only stdlib; no production app fixture hooks."""
import copy
import argparse
import base64
import json
import struct
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fixtures', type=Path, required=True)
parser.add_argument('--evidence', type=Path, required=True)
parser.add_argument('--port', type=int, default=13378)
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
events = args.evidence / 'abs-server-events.jsonl'
events.write_text('')
lock = threading.Lock()
state = {'login': 0, 'bad_password': 0, 'authorize': 0, 'covers': 0, 'play': 0,
         'download_ranges': [], 'tokenized_streams': 0, 'progress': [], 'refresh': 0}

def jwt(payload):
    return 'fixture.' + base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=') + '.signature'

access = jwt({'exp': int(time.time()) + 7200, 'sub': 'fixture-reader'})
api_key = jwt({'type': 'api', 'keyId': 'fixture-key'})

def cover_png():
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    size = 160
    pixels = b''.join(b'\0' + b''.join(bytes((38, 109, 100)) if 15 < x < 145 and 15 < y < 145 else bytes((230, 198, 140)) for x in range(size)) for y in range(size))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')

items = [
    {'id': 'fixture-book', 'libraryId': 'books', 'mediaType': 'book', 'addedAt': 1700000000000,
     'media': {'metadata': {'title': 'The Server Book', 'authorName': 'Fixture Author', 'narratorName': 'Fixture Reader',
                            'description': '<p>A deterministic audiobook from your own shelf.</p>'},
               'duration': 60, 'coverPath': '/covers/book.png', 'numTracks': 1,
               'tracks': [{'index': 1, 'startOffset': 0, 'duration': 60, 'title': 'Server Chapter.wav',
                           'contentUrl': '/audio/fixture.wav', 'mimeType': 'audio/wav'}],
               'chapters': [{'id': 1, 'start': 0, 'end': 30, 'title': 'A beginning'},
                            {'id': 2, 'start': 30, 'end': 60, 'title': 'A return'}]}},
    {'id': 'fixture-other', 'libraryId': 'books', 'mediaType': 'book', 'addedAt': 1700000000001,
     'media': {'metadata': {'title': 'Another Server Book', 'authorName': 'Other Author',
                            'description': 'A generated-cover fallback.'}, 'duration': 60, 'coverPath': '',
               'tracks': [{'index': 1, 'duration': 60, 'title': 'Another.wav', 'contentUrl': '/audio/fixture.wav'}]}}
]

default_items = copy.deepcopy(items)
visual = False

def use_fixture(is_visual):
    global items, visual
    visual = is_visual
    items = copy.deepcopy(default_items)
    if visual:
        first, second = items
        first['media']['metadata'] = {'title': 'Dune of Fixtures', 'authorName': 'E2E Herbert', 'description': 'Dune of Fixtures is served by the e2e fake Audiobookshelf server.'}
        first['media']['duration'] = 48
        first['media']['coverPath'] = ''
        first['media']['tracks'][0]['duration'] = 48
        first['media']['chapters'] = [{'id': 1, 'start': 0, 'end': 48, 'title': 'Dune of Fixtures'}]
        second['media']['metadata'] = {'title': 'The Fixture Hobbit', 'authorName': 'E2E Tolkien', 'description': 'A generated-cover fallback.'}


def save_state():
    (args.evidence / 'abs-server-state.json').write_text(json.dumps(state, indent=2))

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *unused):
        pass  # URLs and Authorization headers may contain credentials.

    def respond(self, value, status=200, mime='application/json', extra=None):
        data = json.dumps(value).encode() if mime == 'application/json' else value
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        for key, val in (extra or {}).items():
            self.send_header(key, val)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def body(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        return json.loads(data) if data else {}

    def record(self, key, value=None):
        with lock:
            if value is None:
                state[key] += 1
            else:
                state[key].append(value)
            save_state()
            with events.open('a') as output:
                output.write(json.dumps({'event': key, 'payload': value}) + '\n')

    def do_POST(self):
        path = urlsplit(self.path).path
        body = self.body()
        if path in ('/_test/reset', '/_test/visual'):
            use_fixture(path == '/_test/visual')
            with lock:
                for key in state:
                    state[key] = [] if key in ('progress', 'download_ranges') else 0
                save_state()
            return self.respond({})
        if path == '/login':
            if self.headers.get('x-return-tokens') != 'true':
                return self.respond({}, 400)
            if body.get('username') != 'reader' or body.get('password') != 'password':
                self.record('bad_password')
                return self.respond({}, 401)
            self.record('login')
            return self.respond({'user': {'username': 'e2e-reader' if visual else 'reader', 'accessToken': access, 'refreshToken': 'fixture-refresh'}})
        if path == '/auth/refresh':
            if self.headers.get('x-refresh-token') != 'fixture-refresh':
                return self.respond({}, 401)
            self.record('refresh')
            return self.respond({'user': {'username': 'e2e-reader' if visual else 'reader', 'accessToken': access, 'refreshToken': 'fixture-refresh'}})
        if not self.authorized():
            return self.respond({}, 401)
        if path == '/api/authorize':
            self.record('authorize')
            return self.respond({'user': {'username': 'e2e-reader' if visual else 'reader', 'id': 'reader'}})
        if path.endswith('/play'):
            self.record('play')
            return self.respond({'id': 'fixture-session', 'libraryItemId': 'fixture-book',
                                 'audioTracks': items[0]['media']['tracks'], 'chapters': items[0]['media']['chapters'], 'currentTime': 12})
        self.respond({}, 404)

    def authorized(self):
        return self.headers.get('Authorization') in ('Bearer ' + access, 'Bearer ' + api_key)

    def do_GET(self):
        parts = urlsplit(self.path)
        path = parts.path
        if path == '/_test/state':
            with lock:
                return self.respond(state)
        if path == '/_test/health':
            return self.respond({'ready': True})
        if path == '/audio/download.wav':
            data = (args.fixtures / 'Chapter 1.wav').read_bytes()
            start = int(self.headers.get('Range', 'bytes=0-').removeprefix('bytes=').split('-')[0])
            self.record('download_ranges', start)
            self.send_response(206 if start else 200)
            self.send_header('Content-Type', 'audio/wav')
            self.send_header('Content-Length', str(len(data) - start))
            self.send_header('ETag', '"durable-v1"')
            if start:
                self.send_header('Content-Range', f'bytes {start}-{len(data)-1}/{len(data)}')
            self.end_headers()
            try:
                for offset in range(start, len(data), 32768):
                    self.wfile.write(data[offset:offset+32768])
                    self.wfile.flush()
                    time.sleep(.15)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == '/audio/fixture.wav':
            if parse_qs(parts.query).get('token') not in ([access], [api_key]):
                return self.respond({}, 401)
            self.record('tokenized_streams')
            data = (args.fixtures / 'Chapter 10.wav').read_bytes()
            range_header = self.headers.get('Range')
            if range_header:
                start, end = range_header.removeprefix('bytes=').split('-', 1)
                start = int(start)
                end = min(int(end) if end else len(data) - 1, len(data) - 1)
                return self.respond(data[start:end+1], 206, 'audio/wav',
                                    {'Content-Range': f'bytes {start}-{end}/{len(data)}', 'Accept-Ranges': 'bytes'})
            return self.respond(data, mime='audio/wav', extra={'Accept-Ranges': 'bytes'})
        if not self.authorized():
            return self.respond({}, 401)
        if path == '/api/libraries':
            return self.respond({'libraries': [{'id': 'books', 'name': 'E2E Shelf' if visual else 'My Audiobooks', 'mediaType': 'book'},
                                               {'id': 'other', 'name': 'Second Library', 'mediaType': 'book'}]})
        if path.startswith('/api/libraries/') and path.endswith('/items'):
            page = int(parse_qs(parts.query).get('page', ['0'])[0])
            limit = int(parse_qs(parts.query).get('limit', ['100'])[0])
            books = items if '/books/' in path else []
            return self.respond({'results': books[page*limit:(page+1)*limit], 'total': len(books), 'page': page, 'limit': limit})
        if path.endswith('/cover'):
            self.record('covers')
            return self.respond(cover_png(), mime='image/png')
        if path == '/api/me/progress':
            return self.respond({'mediaProgress': [{'libraryItemId': 'fixture-book', 'duration': 48 if visual else 60, 'currentTime': 19.2 if visual else 12,
                                                    'progress': .4 if visual else .2, 'isFinished': False, 'lastUpdate': 1700000000000}]})
        if path.startswith('/api/me/progress/'):
            return self.respond({'libraryItemId': path.rsplit('/', 1)[1], 'duration': 48 if visual else 60, 'currentTime': 19.2 if visual else 12, 'progress': .4 if visual else .2, 'isFinished': False})
        if path.startswith('/api/items/'):
            item = next((item for item in items if item['id'] == path.rsplit('/', 1)[1]), None)
            return self.respond(item or {}, 200 if item else 404)
        self.respond({}, 404)

    def do_PATCH(self):
        if not self.authorized():
            return self.respond({}, 401)
        if urlsplit(self.path).path.startswith('/api/me/progress/'):
            payload = self.body()
            if set(payload) != {'duration', 'currentTime', 'progress', 'isFinished'}:
                return self.respond({}, 400)
            self.record('progress', payload)
            return self.respond({})
        self.respond({}, 404)

save_state()
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
