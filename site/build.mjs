#!/usr/bin/env node
// Builds the Unpaged marketing site into site/dist/.
//
//   node site/build.mjs                          # uses site.config.json
//   SITE_URL=https://unpaged.app node site/build.mjs
//
// Zero dependencies. The support, privacy and terms pages are rendered from
// support.md, privacy-policy.md and EULA.md in the repository root, so the
// website and the App Store documents never drift apart.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..");
const src = path.join(here, "src");
const dist = path.join(here, "dist");

const config = JSON.parse(fs.readFileSync(path.join(here, "site.config.json"), "utf8"));
const siteUrl = (process.env.SITE_URL || config.siteUrl).replace(/\/+$/, "");
const basePath = new URL(siteUrl + "/").pathname; // "/" or "/Ebooker/"
const layout = fs.readFileSync(path.join(src, "layout.html"), "utf8");

// Documents rendered from Markdown. `rewrite` maps old public URLs to site pages.
const DOCS = [
  {
    file: "support.md",
    path: "support/",
    description:
      "Help for Unpaged, the audiobook player for iPhone: importing books, free LibriVox classics, Audiobookshelf, AI features, iCloud Sync and purchases.",
  },
  {
    file: "privacy-policy.md",
    path: "privacy/",
    description:
      "How Unpaged handles your data: no account, no analytics or tracking, and no developer server.",
  },
  {
    file: "EULA.md",
    path: "terms/",
    description: "The end user license agreement for Unpaged, including the Unpaged Plus subscription terms.",
  },
];
const LINK_REWRITES = {
  "https://gist.github.com/andreibalu/aca2af2e2176cc453175f708b2481262": "privacy/",
};

// ---------------------------------------------------------------- markdown --
// Covers exactly what the three documents use: #/##/### headings, paragraphs,
// **bold**, *italic*/_italic_, `code`, [links](url), <autolinks>, nested
// ordered/unordered lists, and pipe tables.

const escapeHtml = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function inline(text, ctx) {
  const slots = [];
  const hold = (html) => `\u0000${slots.push(html) - 1}\u0000`;
  let s = text
    .replace(/`([^`]+)`/g, (_, code) => hold(`<code>${escapeHtml(code)}</code>`))
    .replace(/<(https?:\/\/[^>\s]+)>/g, (_, url) => {
      const { href, label } = ctx.link(url);
      return hold(`<a href="${escapeHtml(href)}">${escapeHtml(label)}</a>`);
    })
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, url) =>
      hold(`<a href="${escapeHtml(ctx.link(url).href)}">${inline(label, ctx)}</a>`),
    );
  s = escapeHtml(s)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^\w*])\*(?!\s)(.+?)\*(?!\w)/g, "$1<em>$2</em>")
    .replace(/(^|[^\w])_(?!\s)(.+?)_(?!\w)/g, "$1<em>$2</em>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => slots[+i]);
}

const plain = (s) => s.replace(/[*_`]/g, "").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
const LIST = /^(\s*)([-*]|\d+\.)\s+(.*)$/;
const indentOf = (line) => line.match(/^\s*/)[0].length;
const isBlank = (line) => line.trim() === "";
const isTableStart = (lines, i) =>
  /^\s*\|/.test(lines[i]) && i + 1 < lines.length && /^\s*\|?\s*:?-{3,}/.test(lines[i + 1]);

function markdown(md, ctx) {
  const lines = md.replace(/\r\n?/g, "\n").split("\n");
  const out = [];
  const headings = [];
  const used = new Set();
  const slug = (t) => {
    let base = plain(t).toLowerCase().normalize("NFKD").replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-") || "section";
    let id = base;
    for (let n = 2; used.has(id); n++) id = `${base}-${n}`;
    used.add(id);
    return id;
  };

  function list(i, indent) {
    const ordered = /\d/.test(lines[i].match(LIST)[2]);
    const items = [];
    while (i < lines.length) {
      const line = lines[i];
      if (isBlank(line)) {
        let j = i + 1;
        while (j < lines.length && isBlank(lines[j])) j++;
        const m = lines[j]?.match(LIST);
        if (m && m[1].length === indent && /\d/.test(m[2]) === ordered) { i = j; continue; }
        if (m && m[1].length > indent && items.length) { i = j; continue; }
        break;
      }
      const m = line.match(LIST);
      if (m && m[1].length === indent) { items.push({ text: m[3], children: [] }); i++; continue; }
      if (m && m[1].length > indent && items.length) {
        const nested = list(i, m[1].length);
        items.at(-1).children.push(nested.html);
        i = nested.i;
        continue;
      }
      if (!m && indentOf(line) > indent && items.length) { items.at(-1).text += " " + line.trim(); i++; continue; }
      break;
    }
    const tag = ordered ? "ol" : "ul";
    const body = items.map((it) => `<li>${inline(it.text, ctx)}${it.children.join("")}</li>`).join("\n");
    return { html: `<${tag}>\n${body}\n</${tag}>`, i };
  }

  function table(i) {
    const cells = (row) => row.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
    const head = cells(lines[i]);
    i += 2;
    const rows = [];
    while (i < lines.length && /^\s*\|/.test(lines[i])) rows.push(cells(lines[i++]));
    const th = head.map((h) => `<th scope="col">${inline(h, ctx)}</th>`).join("");
    const tr = rows
      .map((r) => `<tr>${r.map((c, k) => `<td data-label="${escapeHtml(plain(head[k] ?? ""))}">${inline(c, ctx)}</td>`).join("")}</tr>`)
      .join("\n");
    return { html: `<table>\n<thead><tr>${th}</tr></thead>\n<tbody>\n${tr}\n</tbody>\n</table>`, i };
  }

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (isBlank(line)) { i++; continue; }
    const h = line.match(/^(#{1,3})\s+(.*)$/);
    if (h) {
      const level = h[1].length;
      const text = h[2].trim();
      if (level === 1) out.push(`<h1>${inline(text, ctx)}</h1>`);
      else {
        const id = slug(text);
        headings.push({ level, id, text: plain(text) });
        out.push(`<h${level} id="${id}">${inline(text, ctx)}</h${level}>`);
      }
      i++;
      continue;
    }
    if (isTableStart(lines, i)) { const t = table(i); out.push(t.html); i = t.i; continue; }
    const m = line.match(LIST);
    if (m) { const l = list(i, m[1].length); out.push(l.html); i = l.i; continue; }

    const para = [];
    while (i < lines.length && !isBlank(lines[i]) && !/^#{1,3}\s/.test(lines[i]) && !LIST.test(lines[i]) && !isTableStart(lines, i)) {
      para.push(lines[i].trim());
      i++;
    }
    if (para.length === 1 && /^_[^_]+_$/.test(para[0])) {
      out.push(`<p class="updated">${inline(para[0], ctx)}</p>`);
    } else if (para.length > 1 && para.every((l) => l.startsWith("**"))) {
      out.push(`<p class="meta">${para.map((l) => inline(l, ctx)).join("<br>\n")}</p>`);
    } else if (para.length > 1 && para.every((l) => l.length < 60)) {
      // Short stacked lines (a postal address) keep their line breaks.
      out.push(`<p>${para.map((l) => inline(l, ctx)).join("<br>\n")}</p>`);
    } else {
      out.push(`<p>${inline(para.join(" "), ctx)}</p>`);
    }
  }
  const title = plain((md.match(/^#\s+(.*)$/m) || [, "Unpaged"])[1]);
  return { html: out.join("\n"), headings, title };
}

function toc(headings) {
  const hasH3 = headings.some((h) => h.level === 3);
  let html = "";
  let open = false;
  for (const h of headings) {
    if (h.level === 2) {
      if (open) { html += "</ul></li>"; open = false; } else if (html) html += "</li>";
      html += `<li><a href="#${h.id}">${escapeHtml(h.text)}</a>`;
    } else if (hasH3) {
      if (!open) { html += "<ul>"; open = true; }
      html += `<li><a href="#${h.id}">${escapeHtml(h.text)}</a></li>`;
    }
  }
  html += open ? "</ul></li>" : "</li>";
  return `<nav aria-label="On this page"><details class="toc"${hasH3 ? "" : " open"}><summary>On this page</summary><ul>${html}</ul></details></nav>`;
}

// ------------------------------------------------------------------ render --

function rootFor(pagePath, absolute) {
  if (absolute) return basePath;
  const depth = pagePath.split("/").filter(Boolean).length - (pagePath.endsWith("/") ? 0 : 1);
  return depth > 0 ? "../".repeat(depth) : "./";
}

function fill(template, vars) {
  return template.replace(/\{\{(\w+)\}\}/g, (all, key) => (key in vars ? vars[key] : all));
}

function render(page, content) {
  const root = rootFor(page.path, page.absolute);
  const vars = {
    root,
    siteUrl,
    appId: config.appId,
    appStoreUrl: config.appStoreUrl,
    year: String(new Date().getFullYear()),
  };
  const body = fill(content, vars);
  let html = fill(layout, {
    ...vars,
    title: escapeHtml(page.title),
    ogTitle: escapeHtml(page.ogTitle || page.title),
    description: escapeHtml(page.description),
    canonical: `${siteUrl}/${page.path}`,
    bodyClass: page.bodyClass || "",
    currentSupport: page.path === "support/" ? ' aria-current="page"' : "",
    currentPrivacy: page.path === "privacy/" ? ' aria-current="page"' : "",
    content: body,
  });
  if (page.noindex) html = html.replace("<title>", '<meta name="robots" content="noindex">\n<title>');
  const file = path.join(dist, page.out);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, html);
  return file;
}

// Empty dist/ in place (keeps a local preview server's working directory valid).
fs.mkdirSync(dist, { recursive: true });
for (const entry of fs.readdirSync(dist)) fs.rmSync(path.join(dist, entry), { recursive: true, force: true });
fs.cpSync(path.join(src, "assets"), path.join(dist, "assets"), { recursive: true });

const written = [];

for (const name of fs.readdirSync(path.join(src, "pages")).filter((f) => f.endsWith(".html"))) {
  const raw = fs.readFileSync(path.join(src, "pages", name), "utf8");
  const m = raw.match(/^<!--page\s*([\s\S]*?)-->\s*/);
  if (!m) throw new Error(`${name}: missing <!--page {...} --> header`);
  written.push(render(JSON.parse(m[1]), raw.slice(m[0].length)));
}

for (const doc of DOCS) {
  const md = fs.readFileSync(path.join(repo, doc.file), "utf8");
  const root = rootFor(doc.path);
  const ctx = {
    link(url) {
      const target = LINK_REWRITES[url];
      return target ? { href: root + target, label: `${siteUrl}/${target}` } : { href: url, label: url };
    },
  };
  const { html, headings, title } = markdown(md, ctx);
  const firstH2 = html.indexOf("<h2");
  const withToc = firstH2 < 0 ? html : html.slice(0, firstH2) + toc(headings) + "\n" + html.slice(firstH2);
  const others = DOCS.filter((d) => d !== doc)
    .map((d) => `<a href="{{root}}${d.path}">${{ "support/": "Support", "privacy/": "Privacy Policy", "terms/": "Terms of Use" }[d.path]}</a>`)
    .join(" · ");
  const content = `<article class="doc">\n<div class="wrap">\n<div class="doc-body">\n${withToc}\n</div>\n<p class="doc-foot">See also: ${others}</p>\n</div>\n</article>`;
  const short = title.replace(/^Unpaged\s+—\s+/, "");
  written.push(
    render(
      { out: path.join(doc.path, "index.html"), path: doc.path, title: `${short} — Unpaged`, description: doc.description, bodyClass: "doc-page" },
      content,
    ),
  );
}

const pages = ["", "support/", "privacy/", "terms/"];
fs.writeFileSync(
  path.join(dist, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${pages
    .map((p) => `  <url><loc>${siteUrl}/${p}</loc></url>`)
    .join("\n")}\n</urlset>\n`,
);
fs.writeFileSync(path.join(dist, "robots.txt"), `User-agent: *\nAllow: /\n\nSitemap: ${siteUrl}/sitemap.xml\n`);
fs.writeFileSync(path.join(dist, ".nojekyll"), "");

// ------------------------------------------------------------- link check --
// Every local href/src must resolve to a file in dist/, and every #fragment
// must exist on its target page.
let broken = 0;
const idsOf = (file) => new Set([...fs.readFileSync(file, "utf8").matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
for (const file of written) {
  const html = fs.readFileSync(file, "utf8");
  for (const [, attr, ref] of html.matchAll(/\s(href|src)="([^"]+)"/g)) {
    if (/^(https?:|mailto:|data:)/.test(ref)) continue;
    const [refPath, frag] = ref.split("#");
    let target = refPath
      ? refPath.startsWith("/")
        ? path.join(dist, refPath.slice(basePath.length - 1))
        : path.resolve(path.dirname(file), refPath)
      : file;
    if (refPath && (refPath.endsWith("/") || refPath === "." || refPath === "./")) target = path.join(target, "index.html");
    const rel = path.relative(dist, file);
    if (!fs.existsSync(target)) { console.error(`broken ${attr} in ${rel}: ${ref}`); broken++; continue; }
    if (frag && !idsOf(target).has(frag)) { console.error(`missing #${frag} in ${rel}: ${ref}`); broken++; }
  }
}
if (broken) { console.error(`${broken} broken link(s)`); process.exit(1); }
console.log(`Built ${written.length} pages into ${path.relative(process.cwd(), dist) || "."} for ${siteUrl}/ — links OK`);
