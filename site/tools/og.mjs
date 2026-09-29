// Renders tools/og.html to src/assets/img/og.jpg. Needs Playwright + system Chrome
// (e.g. run from a folder where `npm i playwright` has been done) and macOS `sips`.
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));
const png = "/tmp/unpaged-og.png";
const browser = await chromium.launch({ channel: "chrome" });
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
await page.goto("file://" + path.join(here, "og.html"));
await page.screenshot({ path: png });
await browser.close();
execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "85", png, "--out", path.join(here, "../src/assets/img/og.jpg")]);
console.log("wrote src/assets/img/og.jpg");
