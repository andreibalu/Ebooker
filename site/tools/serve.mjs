import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const dist = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../dist');
const port = Number(process.env.PORT || 4400);
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.mjs': 'text/javascript', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.woff2': 'font/woff2', '.png': 'image/png', '.mp4': 'video/mp4', '.xml': 'application/xml', '.txt': 'text/plain' };
http.createServer((req, res) => {
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400); res.end('Bad request'); return; }
  let target = path.resolve(dist, `.${pathname}`);
  if (!target.startsWith(`${dist}/`) && target !== dist) { res.writeHead(403); res.end('Forbidden'); return; }
  if (fs.existsSync(target) && fs.statSync(target).isDirectory()) target = path.join(target, 'index.html');
  const found = fs.existsSync(target) && fs.statSync(target).isFile();
  if (!found) target = path.join(dist, '404.html');
  res.writeHead(found ? 200 : 404, { 'content-type': types[path.extname(target)] || 'application/octet-stream', 'cache-control': 'no-cache' });
  if (req.method === 'HEAD') res.end(); else fs.createReadStream(target).pipe(res);
}).listen(port, '127.0.0.1', () => console.log(`Unpaged local concept: http://127.0.0.1:${port}`));
