/**
 * One-shot migration: turn each post's `bodyHtml` blob into structured content.
 *
 * The posts were ported from a static generator as whole HTML documents —
 * nav, hero, article, CTA and footer all inlined and injected with
 * dangerouslySetInnerHTML, styled by public/site.css. Every post shares the
 * same shape, so it parses cleanly into blocks that React can render.
 *
 * Writes `hero` + `blocks` into each content/blog/<slug>.json, drops
 * `bodyHtml`/`bodyClass`, and emits content/blog/_index.json for the hub.
 *
 *   node scripts/blog-to-blocks.mjs
 */
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { parse } from "node-html-parser";

const DIR = path.join(process.cwd(), "content", "blog");

/** The old pages were emitted at /blog/<slug>/, so their links are relative. */
function absolutize(href, base) {
  if (!href) return href;
  if (/^(https?:|mailto:|tel:|#)/.test(href)) return href;
  if (href.startsWith("/")) return href;
  return new URL(href, `https://x${base}`).pathname + new URL(href, `https://x${base}`).hash;
}

const text = (n) => n.text.replace(/\s+/g, " ").trim();

/** Inline runs: plain text, links, strong, em. Anything else flattens to text. */
function inline(node, base) {
  const out = [];
  for (const child of node.childNodes) {
    if (child.nodeType === 3) {
      const s = child.text.replace(/\s+/g, " ");
      if (s.trim()) out.push({ t: "text", s });
      else if (s && out.length) out.push({ t: "text", s: " " });
      continue;
    }
    const tag = child.rawTagName?.toLowerCase();
    const s = text(child);
    if (!s) continue;
    if (tag === "a") out.push({ t: "link", s, href: absolutize(child.getAttribute("href"), base) });
    else if (tag === "strong" || tag === "b") out.push({ t: "strong", s });
    else if (tag === "em" || tag === "i") out.push({ t: "em", s });
    else out.push({ t: "text", s });
  }
  // Collapse the leading/trailing whitespace-only runs the walk can introduce.
  while (out.length && out[0].t === "text" && !out[0].s.trim()) out.shift();
  while (out.length && out.at(-1).t === "text" && !out.at(-1).s.trim()) out.pop();
  return out;
}

const slugify = (s) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");

function parseHero(root, base) {
  const hero = root.querySelector(".article-hero");
  if (!hero) return null;
  const meta = hero.querySelector(".article-meta");
  return {
    label: text(hero.querySelector(".article-label") ?? { text: "" }) || null,
    title: text(hero.querySelector("h1") ?? { text: "" }),
    summary: text(hero.querySelector(".article-summary") ?? { text: "" }) || null,
    // The trailing "All posts" anchor is chrome, not metadata — the rendered
    // breadcrumb covers it.
    meta: meta ? meta.querySelectorAll("span").map(text).filter(Boolean) : [],
    breadcrumb: (hero.querySelectorAll(".breadcrumb a") ?? []).map((a) => ({
      label: text(a),
      href: absolutize(a.getAttribute("href"), base),
    })),
  };
}

function parseBlocks(body, base) {
  const blocks = [];

  for (const el of body.childNodes.filter((n) => n.nodeType === 1)) {
    const tag = el.rawTagName.toLowerCase();
    const cls = el.classNames ?? "";

    if (cls.includes("answer-box")) {
      blocks.push({
        type: "answer",
        label: text(el.querySelector(".answer-label") ?? { text: "" }) || null,
        copy: text(el.querySelector(".answer-copy") ?? { text: "" }) || null,
        points: el.querySelectorAll(".answer-points li").map(text),
      });
      continue;
    }

    if (cls.includes("article-jump-nav")) {
      blocks.push({
        type: "jumpNav",
        label: text(el.querySelector("span") ?? { text: "" }) || "On this page",
        items: el.querySelectorAll("a").map((a) => ({
          label: text(a),
          href: a.getAttribute("href"),
        })),
      });
      continue;
    }

    if (tag === "h2" || tag === "h3") {
      const s = text(el);
      blocks.push({
        type: "heading",
        level: Number(tag[1]),
        text: s,
        id: el.getAttribute("id") ?? slugify(s),
      });
      continue;
    }

    if (cls.includes("table-scroll") || tag === "table") {
      const table = tag === "table" ? el : el.querySelector("table");
      if (!table) continue;
      blocks.push({
        type: "table",
        head: table.querySelectorAll("thead th").map(text),
        rows: table.querySelectorAll("tbody tr").map((tr) => tr.querySelectorAll("td").map(text)),
      });
      continue;
    }

    if (cls.includes("source-facts")) {
      blocks.push({ type: "sourceFacts", items: el.querySelectorAll("li").map(text) });
      continue;
    }

    if (cls.includes("audit-note")) {
      blocks.push({ type: "note", content: inline(el, base) });
      continue;
    }

    // Checked before the generic list branch: the mini-card grid is itself a
    // <ul>, and each card packs name/title/copy into span/strong/em.
    if (cls.includes("comparison-mini-grid")) {
      blocks.push({
        type: "miniCards",
        cards: el.querySelectorAll(".comparison-mini-card").map((card) => ({
          name: text(card.querySelector("span") ?? { text: "" }) || null,
          title: text(card.querySelector("strong") ?? { text: "" }),
          copy: text(card.querySelector("em") ?? { text: "" }),
          href: absolutize(card.getAttribute("href"), base),
        })),
      });
      continue;
    }

    if (tag === "ul" || tag === "ol") {
      blocks.push({
        type: "list",
        ordered: tag === "ol",
        items: el.querySelectorAll("li").map((li) => inline(li, base)),
      });
      continue;
    }

    if (cls.includes("faq-list")) {
      const items = [];
      for (const child of el.childNodes.filter((n) => n.nodeType === 1)) {
        const t = child.rawTagName.toLowerCase();
        if (t === "h3") items.push({ q: text(child), a: [] });
        else if (t === "p" && items.length) items.at(-1).a.push(inline(child, base));
      }
      blocks.push({ type: "faq", items });
      continue;
    }


    if (cls.includes("article-cta")) {
      const actions = el.querySelectorAll(".article-cta-actions a").map((a) => ({
        label: text(a),
        href: absolutize(a.getAttribute("href"), base),
        primary: (a.classNames ?? "").includes("btn-primary"),
      }));
      blocks.push({
        type: "cta",
        label: text(el.querySelector(".answer-label") ?? { text: "" }) || null,
        title: text(el.querySelector("h2") ?? { text: "" }),
        copy: text(el.querySelector("p:not(.answer-label):not(.article-cta-trust)") ?? { text: "" }),
        actions,
        trust: text(el.querySelector(".article-cta-trust") ?? { text: "" }) || null,
      });
      continue;
    }

    if (cls.includes("article-next")) {
      // Two shapes in the source: a `.related-links` chip row, or a plain
      // sentence with the links inline. Keep whichever the post used.
      const copyEl = el.querySelector("p:not(.answer-label):not(.related-links)");
      blocks.push({
        type: "next",
        label: text(el.querySelector(".answer-label") ?? { text: "" }) || null,
        title: text(el.querySelector("h2") ?? { text: "" }),
        copy: copyEl ? inline(copyEl, base) : null,
        links: el.querySelectorAll(".related-links a").map((a) => ({
          label: text(a),
          href: absolutize(a.getAttribute("href"), base),
        })),
      });
      continue;
    }

    if (tag === "p") {
      const content = inline(el, base);
      if (content.length) blocks.push({ type: "paragraph", content });
      continue;
    }

    // Unhandled node: fail loudly rather than silently dropping copy.
    throw new Error(`unhandled block <${tag} class="${cls}">`);
  }

  return blocks;
}

function migratePost(slug) {
  const file = path.join(DIR, `${slug}.json`);
  const post = JSON.parse(readFileSync(file, "utf8"));
  if (!post.bodyHtml) return post;

  const base = `/blog/${slug}/`;
  const root = parse(post.bodyHtml);
  const body = root.querySelector(".article-body");
  if (!body) throw new Error(`${slug}: no .article-body`);

  const next = { ...post };
  next.hero = parseHero(root, base);
  next.blocks = parseBlocks(body, base);
  delete next.bodyHtml;
  delete next.bodyClass;

  writeFileSync(file, JSON.stringify(next, null, 2) + "\n");
  return next;
}

function migrateHub() {
  const file = path.join(DIR, "_hub.json");
  const hub = JSON.parse(readFileSync(file, "utf8"));
  if (!hub.bodyHtml) return;

  const root = parse(hub.bodyHtml);
  const heroEl = root.querySelector(".blog-hero");
  const next = { ...hub };
  next.hero = {
    label: text(heroEl.querySelector(".blog-label") ?? { text: "" }) || null,
    title: text(heroEl.querySelector("h1") ?? { text: "" }),
    summary: text(heroEl.querySelector("p:not(.blog-label)") ?? { text: "" }) || null,
  };
  next.archive = {
    kicker: text(root.querySelector(".archive-kicker") ?? { text: "" }) || null,
    title: text(root.querySelector(".archive-head h2") ?? { text: "" }) || null,
  };
  next.posts = root.querySelectorAll(".blog-post-card").map((card) => {
    const [kicker, date] = text(card.querySelector(".blog-card-topline") ?? { text: "" })
      .split("·")
      .map((s) => s.trim());
    return {
      slug: (card.getAttribute("href") ?? "").replace(/\/$/, ""),
      kicker: kicker || null,
      date: date || null,
      title: text(card.querySelector("h3") ?? { text: "" }),
      summary: text(card.querySelector(".blog-card-summary") ?? { text: "" }),
    };
  });
  delete next.bodyHtml;
  delete next.bodyClass;

  writeFileSync(file, JSON.stringify(next, null, 2) + "\n");
}

const slugs = readdirSync(DIR)
  .filter((f) => f.endsWith(".json") && f !== "_hub.json" && f !== "_index.json")
  .map((f) => f.replace(/\.json$/, ""));

for (const slug of slugs) {
  const post = migratePost(slug);
  console.log(`${slug}: ${post.blocks?.length ?? 0} blocks`);
}
migrateHub();
console.log("hub: done");
