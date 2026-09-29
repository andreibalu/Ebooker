// Local preview that behaves like GitHub Pages: directory index.html, 404.html
// for unknown paths, and an optional project base path.
//   node site/tools/serve.mjs                   -> http://127.0.0.1:8140/
//   node site/tools/serve.mjs --base /Ebooker/  -> http://127.0.0.1:8140/Ebooker/
// Build with a matching SITE_URL first, e.g. SITE_URL=http://127.0.0.1:8140/Ebooker node site/build.mjs
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dist = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist");
const arg = (name, fallback) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : fallback; };
const base = arg("--base", "/");
const port = Number(arg("--port", 8140));
const types = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".xml": "application/xml", ".txt": "text/plain" };
http.createServer((req, res) => {
  const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
  let file = url.startsWith(base) ? path.join(dist, url.slice(base.length)) : null;
  if (file && !file.startsWith(dist)) file = null;
  if (file && fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  const found = file && fs.existsSync(file);
  const target = found ? file : path.join(dist, "404.html");
  res.writeHead(found ? 200 : 404, { "content-type": types[path.extname(target)] || "application/octet-stream" });
  fs.createReadStream(target).pipe(res);
}).listen(port, "127.0.0.1", () => console.log(`http://127.0.0.1:${port}${base}`));
