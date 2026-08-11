#!/usr/bin/env node

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { footerHtml } from "./lib/footer.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
// Keep the editorial source and the checked-in Pages output in lockstep.
const content = JSON.parse(await readFile(path.join(root, "content/features.json"), "utf8"));
const output = path.join(root, "docs/features");
const site = "https://gojo.rohoswagger.com";
const esc = (value) => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");

function chrome({ title, description, canonical, schema, body }) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${esc(title)}</title><meta name="description" content="${esc(description)}"><link rel="canonical" href="${canonical}"><meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}"><meta property="og:type" content="article"><meta property="og:url" content="${canonical}"><meta property="og:image" content="${site}/assets/og.jpg"><meta name="twitter:card" content="summary_large_image"><link rel="icon" href="../../favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="../../site.css?v=20260810-footer"><script type="application/ld+json">${JSON.stringify(schema)}</script></head><body class="article-shell">${body}</body></html>`;
}

const nav = () => `<header class="site-header"><a class="brand" href="../../" aria-label="Gojo home">Gojo</a><nav class="nav" aria-label="Primary"><a href="../">Features</a><a href="../../blog/">Blog</a><a href="../../alternatives/">Alternatives</a><a href="https://downloads.rohoswagger.com/Gojo.dmg">Download</a></nav></header>`;
const articleFooter = await footerHtml("../../");
const hubFooter = await footerHtml("../");

function featurePage(feature) {
  const title = `${feature.name} for MacBook notch | Gojo`;
  const description = `${feature.what} Learn how Gojo's ${feature.name.toLowerCase()} is useful on a MacBook.`;
  const canonical = `${site}/features/${feature.slug}/`;
  const details = feature.details.map((detail) => `<li>${esc(detail)}</li>`).join("");
  const schema = { "@context": "https://schema.org", "@graph": [{ "@type": "BlogPosting", headline: title, description, url: canonical, datePublished: content.updated, dateModified: content.updated, author: { "@type": "Organization", name: "Gojo" }, about: { "@type": "SoftwareApplication", name: "Gojo", operatingSystem: "macOS 14+", url: site } }, { "@type": "FAQPage", mainEntity: [{ "@type": "Question", name: `What is Gojo ${feature.name}?`, acceptedAnswer: { "@type": "Answer", text: feature.what } }, { "@type": "Question", name: `Why use Gojo ${feature.name}?`, acceptedAnswer: { "@type": "Answer", text: feature.useful } }] }] };
  const body = `<div class="article-top">${nav()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Features</a></nav><p class="article-label">Gojo feature</p><h1>${esc(feature.name)}</h1><p class="article-summary">${esc(feature.tagline)}</p><div class="article-meta"><span>Updated ${content.updated}</span><span>macOS 14+</span></div></div></section></main></div><main class="article-main"><article class="article-body article-reader"><div class="answer-box"><p class="answer-label">What it does</p><p class="answer-copy">${esc(feature.what)}</p></div><h2>Why it is useful</h2><p>${esc(feature.useful)}</p><h2>How ${esc(feature.name)} works in Gojo</h2><ul class="source-facts">${details}</ul><h2>Good to know</h2><p>${esc(feature.caveat)}</p><h2>One workspace, not another standalone utility</h2><p>${esc(feature.name)} is one part of Gojo’s MacBook-notch workspace. Keep the tools you use visible, hide the rest, and reach media, windows, clipboard, files, display controls, and more from the same native surface.</p><h2>Related Gojo feature</h2><p><a href="${feature.related}">See the relevant Gojo product detail</a>, or browse the <a href="../">complete feature library</a>.</p><section class="article-cta" aria-labelledby="try-gojo-title"><p class="answer-label">Try it on your Mac</p><h2 id="try-gojo-title">Put ${esc(feature.name.toLowerCase())} one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.rohoswagger.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private by design</p></section></article></main>${articleFooter}`;
  return chrome({ title, description, canonical, schema, body });
}

function hub() {
  const cards = content.features.map((feature) => `<li><a class="alternative-card" href="${feature.slug}/"><span>Gojo feature</span><h3>${esc(feature.name)}</h3><p>${esc(feature.tagline)}</p><strong>See how it works <span aria-hidden="true">→</span></strong></a></li>`).join("");
  const canonical = `${site}/features/`;
  const schema = { "@context": "https://schema.org", "@type": "CollectionPage", name: "Gojo features", url: canonical, dateModified: content.updated, mainEntity: { "@type": "ItemList", numberOfItems: content.features.length, itemListElement: content.features.map((feature, index) => ({ "@type": "ListItem", position: index + 1, name: feature.name, url: `${canonical}${feature.slug}/` })) } };
  const body = `<div class="article-top">${nav()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Features</span></nav><p class="article-label">Gojo features</p><h1>MacBook-notch tools for the jobs you repeat every day</h1><p class="article-summary">Each Gojo feature is built to keep a useful Mac control close without turning your menu bar into a stack of separate utilities.</p><div class="article-meta"><span>Updated ${content.updated}</span><span>${content.features.length} feature guides</span></div></div></section></main></div><main class="article-main"><article class="article-body article-reader"><div class="answer-box"><p class="answer-label">What Gojo does</p><p class="answer-copy">Gojo combines private on-device dictation, media, clipboard history, windows, file staging, display comfort, and glanceable tools in one native MacBook-notch workspace.</p></div><h2>Explore every Gojo feature</h2><ol class="alternative-grid">${cards}</ol><section class="article-cta" aria-labelledby="features-cta"><p class="answer-label">Ready to try the workspace?</p><h2 id="features-cta">Start with the tools you use most.</h2><p>Gojo gives you a fully unlocked three-day trial with no card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.rohoswagger.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div></section></article></main>${hubFooter}`;
  return chrome({ title: "Gojo features: MacBook-notch productivity tools", description: "Explore Gojo's MacBook-notch features: private dictation, media, clipboard, windows, files, display controls, calendar, battery, camera mirror, and shortcuts.", canonical, schema, body });
}

for (const feature of content.features) {
  if (!/^[a-z0-9-]+$/.test(feature.slug) || !feature.name || !feature.what || !feature.useful || !feature.details?.length) throw new Error(`Incomplete feature: ${feature.slug}`);
  const folder = path.join(output, feature.slug);
  await mkdir(folder, { recursive: true });
  await writeFile(path.join(folder, "index.html"), featurePage(feature));
}
await mkdir(output, { recursive: true });
await writeFile(path.join(output, "index.html"), hub());
console.log(`Generated ${content.features.length} feature guides and the features hub.`);
