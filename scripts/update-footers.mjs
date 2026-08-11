#!/usr/bin/env node

// Rewrites the <footer class="footer">…</footer> block in every docs page so the
// full feature and alternative libraries are linked from anywhere on the site.
import { readdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { footerHtml } from "./lib/footer.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const docs = path.join(root, "docs");

async function htmlFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const found = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...(await htmlFiles(full)));
    else if (entry.name.endsWith(".html")) found.push(full);
  }
  return found;
}

let updated = 0;
for (const file of await htmlFiles(docs)) {
  const html = await readFile(file, "utf8");
  const match = /[ \t]*<footer class="footer[^"]*">[\s\S]*?<\/footer>(\n?)/.exec(html);
  if (!match) continue;

  const depth = path.relative(docs, path.dirname(file)).split(path.sep).filter(Boolean).length;
  const footer = await footerHtml("../".repeat(depth));
  const next = html.slice(0, match.index) + footer + match[1] + html.slice(match.index + match[0].length);
  if (next === html) continue;

  await writeFile(file, next);
  updated += 1;
}

console.log(`Updated footers on ${updated} pages.`);
