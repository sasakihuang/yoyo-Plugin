// Screenshot every manager page from a built frontend dist.
// Usage: node scripts/ui-preview.mjs <distDir> <outDir>
// Requires `playwright` (or playwright-core + CHROMIUM_PATH env) resolvable
// from the CURRENT WORKING DIRECTORY's node_modules.
// Runs the app with a stubbed Tauri backend: pages render their layout and
// static copy, which is exactly what a visual promo/ads review needs.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const [distDir, outDir] = process.argv.slice(2);
if (!distDir || !outDir) {
  console.error("usage: node ui-preview.mjs <distDir> <outDir>");
  process.exit(2);
}
const req = createRequire(path.join(process.cwd(), "package.json"));
let chromium;
try {
  ({ chromium } = req("playwright"));
} catch {
  ({ chromium } = req("playwright-core"));
}

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

const server = http.createServer((request, response) => {
  const url = decodeURIComponent(new URL(request.url, "http://x").pathname);
  let file = path.join(distDir, url === "/" ? "index.html" : url);
  if (!file.startsWith(path.resolve(distDir)) && !file.startsWith(distDir)) {
    response.writeHead(403).end();
    return;
  }
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(distDir, "index.html");
  response.writeHead(200, { "content-type": MIME[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(response);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  args: ["--no-sandbox", "--force-color-profile=srgb", "--disable-lcd-text"],
});
const page = await browser.newPage({ viewport: { width: 1440, height: 940 }, deviceScaleFactor: 1 });
await page.addInitScript(() => {
  window.__TAURI_INTERNALS__ = {
    invoke: () => Promise.resolve(null),
    transformCallback: () => Math.floor(Math.random() * 100000),
    unregisterCallback: () => {},
    metadata: { currentWindow: { label: "main" }, currentWebview: { label: "main" } },
    plugins: {},
    convertFileSrc: (p) => p,
  };
  // Freeze animations/carets so identical pages hash identically.
  const style = document.createElement("style");
  style.textContent = "*, *::before, *::after { animation: none !important; transition: none !important; caret-color: transparent !important; }";
  document.addEventListener("DOMContentLoaded", () => document.head.appendChild(style));
});
await page.goto(`http://127.0.0.1:${port}/`);
await page.waitForTimeout(2500);

const labels = await page.$$eval("button.nav-item", (els) => els.map((e) => (e.getAttribute("title") || e.textContent || "").trim()));
const manifest = [];
for (let i = 0; i < labels.length; i++) {
  const label = labels[i];
  try {
    await page.locator("button.nav-item").nth(i).click();
    await page.waitForTimeout(900);
    const file = `page-${String(i).padStart(2, "0")}.png`;
    await page.screenshot({ path: path.join(outDir, file) });
    manifest.push({ label, file });
  } catch (error) {
    manifest.push({ label, file: null, error: String(error).slice(0, 200) });
  }
}
fs.writeFileSync(path.join(outDir, "pages.json"), JSON.stringify(manifest, null, 2));
console.log(`captured ${manifest.filter((m) => m.file).length}/${labels.length} pages -> ${outDir}`);
await browser.close();
server.close();
