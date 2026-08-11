#!/usr/bin/env node

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { footerHtml } from "./lib/footer.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const contentPath = path.join(root, "content", "alternatives.json");
const outputRoot = path.join(root, "docs", "alternatives");
const siteUrl = "https://gojo.rohoswagger.com";

const escapeHtml = (value) => String(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#39;");

function assertAlternative(alternative) {
  const required = ["slug", "name", "category", "officialUrl", "officialFacts", "bestFor", "gojoFit", "tradeoff", "relatedComparison"];
  for (const field of required) {
    if (!alternative[field] || (Array.isArray(alternative[field]) && alternative[field].length === 0)) {
      throw new Error(`${alternative.slug || "unknown alternative"} is missing ${field}`);
    }
  }
  if (!/^[a-z0-9-]+$/.test(alternative.slug)) throw new Error(`Invalid slug: ${alternative.slug}`);
  if (!alternative.officialUrl.startsWith("https://")) throw new Error(`${alternative.name} needs an HTTPS primary source`);
}

function pageChrome({ title, description, canonical, schema, body }) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
  <link rel="canonical" href="${canonical}">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:type" content="article">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${siteUrl}/assets/og.jpg">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" href="../../favicon.svg" type="image/svg+xml">
  <link rel="stylesheet" href="../../site.css?v=20260810-landing">
  <script type="application/ld+json">${JSON.stringify(schema)}</script>
</head>
<body class="article-shell">
  ${body}
</body>
</html>`;
}

function navigation() {
  return `<header class="site-header"><a class="brand" href="../../" aria-label="Gojo home">Gojo</a><nav class="nav" aria-label="Primary"><a href="../../blog/">Blog</a><a href="../">Alternatives</a><a href="https://downloads.rohoswagger.com/Gojo.dmg">Download</a></nav></header>`;
}

const articleFooter = await footerHtml("../../");
const hubFooter = await footerHtml("../");

function articlePage(alternative, data) {
  const title = `${alternative.name} alternative: is Gojo a good fit for Mac?`;
  const description = `An evidence-led ${alternative.name} alternative guide for Mac: published product facts, workflow tradeoffs, and where Gojo fits.`;
  const canonical = `${siteUrl}/alternatives/${alternative.slug}/`;
  const facts = alternative.officialFacts.map((fact) => `<li>${escapeHtml(fact)}</li>`).join("\n");
  const schema = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "BlogPosting",
        headline: title,
        description,
        url: canonical,
        datePublished: data.updated,
        dateModified: data.updated,
        author: { "@type": "Organization", name: "Gojo" },
        mentions: [
          { "@type": "SoftwareApplication", name: "Gojo", url: data.gojo.url, operatingSystem: "macOS" },
          { "@type": "SoftwareApplication", name: alternative.name, url: alternative.officialUrl, operatingSystem: "macOS" }
        ],
        citation: [alternative.officialUrl, data.gojo.url]
      },
      {
        "@type": "FAQPage",
        mainEntity: [
          { "@type": "Question", name: `Is Gojo an alternative to ${alternative.name}?`, acceptedAnswer: { "@type": "Answer", text: `Yes, if you want ${alternative.gojoFit}. ${alternative.tradeoff}` } },
          { "@type": "Question", name: `Who should choose ${alternative.name}?`, acceptedAnswer: { "@type": "Answer", text: `${alternative.name} is best for ${alternative.bestFor}.` } }
        ]
      }
    ]
  };
  const body = `<div class="article-top">${navigation()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Alternatives</a></nav><p class="article-label">Alternative guide</p><h1>${escapeHtml(alternative.name)} alternative: is Gojo a good fit for Mac?</h1><p class="article-summary">${escapeHtml(alternative.name)} is for ${escapeHtml(alternative.bestFor)}. Gojo is for ${escapeHtml(alternative.gojoFit)}.</p><div class="article-meta"><span>Updated ${data.updated}</span><span>Primary source checked</span></div></div></section></main></div>
<main class="article-main"><article class="article-body article-reader comparison-article">
  <div class="answer-box"><p class="answer-label">Short answer</p><p class="answer-copy">Choose ${escapeHtml(alternative.name)} when you want ${escapeHtml(alternative.bestFor)}. Choose Gojo when you want ${escapeHtml(alternative.gojoFit)}.</p><p>${escapeHtml(alternative.tradeoff)}</p></div>
  <nav class="article-jump-nav" aria-label="On this page"><span>On this page</span><a href="#facts">Published facts</a><a href="#fit">Best fit</a><a href="#faq">FAQ</a></nav>
  <h2 id="facts">Published facts about ${escapeHtml(alternative.name)}</h2>
  <p>These are product facts from <a href="${escapeHtml(alternative.officialUrl)}" rel="external noopener">${escapeHtml(alternative.name)}’s official site</a>, checked ${data.updated}. They describe the product rather than score it.</p>
  <ul class="source-facts">${facts}</ul>
  <h2 id="fit">Which Mac workflow fits better?</h2>
  <div class="table-scroll"><table class="comparison-table"><thead><tr><th>Question</th><th>${escapeHtml(alternative.name)}</th><th>Gojo</th></tr></thead><tbody><tr><td>Primary fit</td><td>${escapeHtml(alternative.bestFor)}</td><td>${escapeHtml(alternative.gojoFit)}</td></tr><tr><td>Product shape</td><td>${escapeHtml(alternative.category)}</td><td>Focused MacBook-notch productivity workspace</td></tr><tr><td>Try first</td><td>Check the developer’s current product page</td><td>${escapeHtml(data.gojo.trial)}</td></tr></tbody></table></div>
  <h3>Choose ${escapeHtml(alternative.name)} when its specialty is the point</h3><p>${escapeHtml(alternative.name)} is the more direct choice if your priority is ${escapeHtml(alternative.bestFor)}. A specialist can be the better tool when that workflow is where you spend most of your time.</p>
  <h3>Choose Gojo for an integrated daily loop</h3><p>Gojo combines private on-device dictation, windows, clipboard history, file staging, media, and display controls. It is designed for MacBook owners who would rather reach one quiet notch surface than assemble several narrow utilities.</p>
  <h2>Sources and editorial method</h2><p>Primary source checked ${data.updated}: <a href="${escapeHtml(alternative.officialUrl)}" rel="external noopener">${escapeHtml(alternative.name)} official site</a>. Gojo product claims are based on the <a href="../../">official Gojo site</a>. Product features, availability, and pricing can change; verify the developer’s current information before buying.</p>
  <h2 id="faq">FAQ</h2><section class="faq-list"><h3>Is Gojo an alternative to ${escapeHtml(alternative.name)}?</h3><p>Yes, when you want ${escapeHtml(alternative.gojoFit)}. ${escapeHtml(alternative.tradeoff)}</p><h3>Who should choose ${escapeHtml(alternative.name)}?</h3><p>${escapeHtml(alternative.name)} is best for ${escapeHtml(alternative.bestFor)}.</p></section>
  <section class="article-cta" aria-labelledby="try-gojo-title"><p class="answer-label">Want the focused option?</p><h2 id="try-gojo-title">Put daily Mac controls one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.rohoswagger.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private on-device dictation</p></section>
  <section class="article-next"><p class="answer-label">Go deeper</p><h2>Compare the products directly</h2><p><a href="${alternative.relatedComparison}">Read Gojo vs ${escapeHtml(alternative.name)}</a> for a fuller workflow comparison, or return to the <a href="../">Gojo alternatives hub</a>.</p></section>
</article></main>${articleFooter}`;
  return pageChrome({ title, description, canonical, schema, body });
}

function hubPage(data) {
  const cards = data.alternatives.map((alternative) => `<li><a class="alternative-card" href="${alternative.slug}/"><span>${escapeHtml(alternative.category)}</span><h3>${escapeHtml(alternative.name)}</h3><p>Best for ${escapeHtml(alternative.bestFor)}.</p><strong>Read the evidence-led guide <span aria-hidden="true">→</span></strong></a></li>`).join("\n");
  const canonical = `${siteUrl}/alternatives/`;
  const schema = { "@context": "https://schema.org", "@graph": [{ "@type": "CollectionPage", name: "Gojo alternatives for Mac", url: canonical, dateModified: data.updated, mainEntity: { "@type": "ItemList", numberOfItems: data.alternatives.length, itemListElement: data.alternatives.map((alternative, index) => ({ "@type": "ListItem", position: index + 1, name: `${alternative.name} alternative guide`, url: `${canonical}${alternative.slug}/` })) } }] };
  const body = `<div class="article-top">${navigation()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Alternatives</span></nav><p class="article-label">Mac utility alternatives</p><h1>Gojo alternatives for Mac: find the workflow that fits</h1><p class="article-summary">Compare focused notch utilities, broader productivity layers, and specialist Mac apps using published product facts—not a generic winner.</p><div class="article-meta"><span>Updated ${data.updated}</span><span>${data.alternatives.length} evidence-led guides</span></div></div></section></main></div>
<main class="article-main"><article class="article-body article-reader comparison-article"><div class="answer-box"><p class="answer-label">Short answer</p><p class="answer-copy">Gojo is the focused choice for private on-device dictation, windows, clipboard, files, media, and display controls in one MacBook-notch workspace. An alternative may fit better when you need deep automation, a dedicated specialist tool, extensive widgets, or a free open-source app.</p></div><h2>Browse Gojo alternatives by product fit</h2><p>Each guide links to the alternative’s official product page, separates published facts from editorial guidance, and explains where Gojo is the more cohesive option.</p><ol class="alternative-grid">${cards}</ol><h2>How to choose fairly</h2><ol><li><strong>Start with the repeated job.</strong> A dedicated window, clipboard, keyboard, or display tool can be better when it solves the one problem you have.</li><li><strong>Check the interaction model.</strong> Gojo favors a visible, hoverable notch surface. Some alternatives are keyboard-first, automation-first, or more widget-heavy.</li><li><strong>Verify current details before purchase.</strong> Features, system requirements, device limits, and pricing change. Every guide dates its primary-source check.</li></ol><section class="article-cta" aria-labelledby="hub-cta-title"><p class="answer-label">Prefer one cohesive utility?</p><h2 id="hub-cta-title">Try Gojo’s focused MacBook workspace.</h2><p>${escapeHtml(data.gojo.summary)}.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.rohoswagger.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">${escapeHtml(data.gojo.trial)} &middot; Signed &amp; notarized</p></section></article></main>${hubFooter}`;
  return pageChrome({ title: "Best Gojo alternatives for Mac in 2026", description: "Compare Gojo alternatives for Mac by workflow, with official sources, dated facts, and clear guidance on where Gojo fits.", canonical, schema, body });
}

async function main() {
  const data = JSON.parse(await readFile(contentPath, "utf8"));
  if (!/^\d{4}-\d{2}-\d{2}$/.test(data.updated)) throw new Error("updated must be YYYY-MM-DD");
  const slugs = new Set();
  for (const alternative of data.alternatives) {
    assertAlternative(alternative);
    if (slugs.has(alternative.slug)) throw new Error(`Duplicate slug: ${alternative.slug}`);
    slugs.add(alternative.slug);
    const directory = path.join(outputRoot, alternative.slug);
    await mkdir(directory, { recursive: true });
    await writeFile(path.join(directory, "index.html"), articlePage(alternative, data));
  }
  await mkdir(outputRoot, { recursive: true });
  await writeFile(path.join(outputRoot, "index.html"), hubPage(data));
  console.log(`Generated ${data.alternatives.length} alternative guides and the alternatives hub.`);
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
