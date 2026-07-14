// Compare two ui-preview output dirs (old vs new) page by page.
// Usage: node scripts/ui-compare.mjs <oldDir> <newDir> <reportJson>
// Emits JSON: [{label, status: same|changed|new|removed, diffPct, oldFile, newFile}]
// Requires `pixelmatch` + `pngjs` resolvable from the cwd's node_modules.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const [oldDir, newDir, reportPath] = process.argv.slice(2);
const req = createRequire(path.join(process.cwd(), "package.json"));
const { PNG } = req("pngjs");
let pixelmatch = req("pixelmatch");
if (pixelmatch && typeof pixelmatch !== "function") pixelmatch = pixelmatch.default;

const load = (dir) => {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "pages.json"), "utf8"));
  return new Map(manifest.filter((m) => m.file).map((m) => [m.label, path.join(dir, m.file)]));
};
const oldPages = load(oldDir);
const newPages = load(newDir);

const results = [];
for (const [label, newFile] of newPages) {
  const oldFile = oldPages.get(label);
  if (!oldFile) {
    results.push({ label, status: "new", newFile });
    continue;
  }
  const a = PNG.sync.read(fs.readFileSync(oldFile));
  const b = PNG.sync.read(fs.readFileSync(newFile));
  if (a.width !== b.width || a.height !== b.height) {
    results.push({ label, status: "changed", diffPct: 100, oldFile, newFile });
    continue;
  }
  const mismatched = pixelmatch(a.data, b.data, null, a.width, a.height, { threshold: 0.12 });
  const diffPct = (mismatched / (a.width * a.height)) * 100;
  // Rendering here is deterministic (animations frozen, sRGB forced), so be
  // strict: a dozen pixels is already a real change — a small text link (the
  // kind ads hide in) is only ~100-200 pixels on a 1440x940 page.
  results.push({ label, status: mismatched > 12 ? "changed" : "same", diffPct: Number(diffPct.toFixed(4)), oldFile, newFile });
}
for (const [label, oldFile] of oldPages) {
  if (!newPages.has(label)) results.push({ label, status: "removed", oldFile });
}
fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
const changed = results.filter((r) => r.status !== "same");
console.log(`compared ${results.length} pages; ${changed.length} changed/new/removed`);
