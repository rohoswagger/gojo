#!/usr/bin/env node
/**
 * extract-blog.mjs
 *
 * One-off extractor that reads the hand-authored static blog pages from
 * docs/blog/**\/index.html and turns each one into structured JSON under
 * web/content/blog/*.json.
 *
 * Why this exists: the blog posts rank in search and their JSON-LD is a
 * cross-linked graph (shared @id anchors like https://trygojo.com/#organization).
 * Byte fidelity matters more than convenience, so instead of hand-porting the
 * markup into JSX we parse the source HTML and preserve:
 *   - all <meta> driven SEO fields (title, description, canonical, og:*, twitter:*,
 *     article:*, author, robots)
 *   - the full parsed JSON-LD graph, verbatim (json.loads -> json.dumps identity,
 *     no re-keying / renumbering / re-ordering)
 *   - the raw innerHTML of everything in <body> between the closing </header>
 *     and the opening <footer> (i.e. the page-specific content, independent of
 *     however many <main> wrappers a given page happens to use)
 *
 * Run with: node scripts/extract-blog.mjs
 */
import { parse } from "node-html-parser";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, "..");
const docsBlogRoot = path.resolve(webRoot, "..", "docs", "blog");
const outDir = path.resolve(webRoot, "content", "blog");

const SLUGS = [
  "best-droppy-alternatives",
  "best-macos-accessibility-permission-apps",
  "best-macos-notch-utilities",
  "gojo-vs-alcove",
  "gojo-vs-alttab",
  "gojo-vs-bettertouchtool",
  "gojo-vs-boring-notch",
  "gojo-vs-droppy",
  "gojo-vs-dynamiclake",
  "gojo-vs-flux",
  "gojo-vs-karabiner-elements",
  "gojo-vs-maccy",
  "gojo-vs-notchnook",
  "gojo-vs-raycast",
  "gojo-vs-rectangle",
];

function metaContent(root, selector) {
  const el = root.querySelector(selector);
  return el ? el.getAttribute("content") ?? null : null;
}

function collectMetaMap(root, prefix) {
  // Collects every <meta property="prefix:*" content="..."> (or name=) into
  // an ordered key/value map, preserving source order and duplicate-safe keys.
  const out = {};
  const metas = root.querySelectorAll("meta");
  for (const m of metas) {
    const prop = m.getAttribute("property") || m.getAttribute("name");
    if (prop && prop.startsWith(prefix + ":")) {
      out[prop] = m.getAttribute("content") ?? "";
    }
  }
  return out;
}

function extractBody(html) {
  // Straight string slicing (not a DOM re-serialize) so the extracted markup
  // is byte-identical to the source: the entire <body> contents -- header,
  // hero, article/archive content, and footer, exactly as authored. We keep
  // header and footer in bodyHtml (rather than reimplementing them as JSX)
  // because it's the only way to guarantee true byte fidelity, and because
  // site.css relies on child-combinator selectors (e.g. ".shell > .site-header")
  // that only match when header/footer stay nested exactly where the source
  // put them. The relative hrefs inside (../, ../../) still resolve correctly
  // because the Next static export reproduces the same directory depth as
  // docs/blog/**.
  const bodyTagStart = html.indexOf("<body");
  const bodyOpenEnd = html.indexOf(">", bodyTagStart) + 1;
  const bodyClose = html.indexOf("</body>");
  if (bodyTagStart === -1 || bodyOpenEnd === 0 || bodyClose === -1) {
    throw new Error("expected a <body>...</body> in source");
  }
  const bodyOpenTag = html.slice(bodyTagStart, bodyOpenEnd);
  const classMatch = bodyOpenTag.match(/class="([^"]*)"/);
  const bodyClass = classMatch ? classMatch[1] : null;
  const bodyHtml = html.slice(bodyOpenEnd, bodyClose).trim();
  return { bodyClass, bodyHtml };
}

function extractOne(htmlPath, slug) {
  const html = readFileSync(htmlPath, "utf8");
  const root = parse(html, { comment: false });

  const title = root.querySelector("title")?.text ?? null;
  const description = metaContent(root, 'meta[name="description"]');
  const canonicalEl = root.querySelector('link[rel="canonical"]');
  const canonical = canonicalEl ? canonicalEl.getAttribute("href") : null;

  const og = collectMetaMap(root, "og");
  const twitter = collectMetaMap(root, "twitter");

  const article = {
    published_time: metaContent(root, 'meta[property="article:published_time"]'),
    modified_time: metaContent(root, 'meta[property="article:modified_time"]'),
    section: metaContent(root, 'meta[property="article:section"]'),
    author: metaContent(root, 'meta[name="author"]'),
    robots: metaContent(root, 'meta[name="robots"]'),
  };

  const ldScript = root.querySelector('script[type="application/ld+json"]');
  let jsonLd = null;
  if (ldScript) {
    const raw = ldScript.textContent ?? ldScript.rawText ?? "";
    jsonLd = JSON.parse(raw);
  }

  const { bodyClass, bodyHtml } = extractBody(html);

  return {
    slug,
    title,
    description,
    canonical,
    og,
    twitter,
    article,
    jsonLd,
    bodyClass,
    bodyHtml,
  };
}

function main() {
  if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });

  // Hub page
  const hubPath = path.join(docsBlogRoot, "index.html");
  const hub = extractOne(hubPath, "_hub");
  writeFileSync(
    path.join(outDir, "_hub.json"),
    JSON.stringify(hub, null, 2) + "\n"
  );
  console.log("wrote _hub.json");

  // Post pages
  for (const slug of SLUGS) {
    const p = path.join(docsBlogRoot, slug, "index.html");
    const data = extractOne(p, slug);
    writeFileSync(
      path.join(outDir, `${slug}.json`),
      JSON.stringify(data, null, 2) + "\n"
    );
    console.log(`wrote ${slug}.json`);
  }

  console.log(`\nDone. ${SLUGS.length + 1} files written to ${outDir}`);
}

main();
