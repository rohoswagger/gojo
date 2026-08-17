import alternativesData from "@/content/alternatives.json"

// Ported from gojo/scripts/generate-alternative-pages.mjs. HTML structure,
// class names, and copy templates are kept verbatim; only the parts that
// depended on Node file I/O or the static-page <head> are removed (Next's
// Metadata API and app/layout.tsx own those instead). Internal relative
// links (nav, breadcrumbs, CTAs) are left exactly as the generator wrote
// them because Next serves each route at the same URL depth as the
// original static export, so the relative resolution is identical.

export type Alternative = {
  slug: string
  name: string
  category: string
  officialUrl: string
  officialFacts: string[]
  bestFor: string
  gojoFit: string
  tradeoff: string
  relatedComparison: string
}

type AlternativesData = {
  updated: string
  gojo: { name: string; url: string; trial: string; summary: string }
  alternatives: Alternative[]
}

const data = alternativesData as AlternativesData
export const siteUrl = "https://trygojo.com"

export const escapeHtml = (value: unknown) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")

export function getAlternatives(): Alternative[] {
  return data.alternatives
}

export function getAlternative(slug: string): Alternative | undefined {
  return data.alternatives.find((alternative) => alternative.slug === slug)
}

export function getAlternativesUpdated(): string {
  return data.updated
}

function navigation() {
  return `<header class="site-header"><a class="brand" href="../../" aria-label="Gojo home">Gojo</a><nav class="nav" aria-label="Primary"><a href="../../blog/">Blog</a><a href="../">Alternatives</a><a href="/downloads/">Download</a></nav></header>`
}

export function alternativeTitle(alternative: Alternative) {
  return `${alternative.name} alternative: is Gojo a good fit for Mac?`
}

export function alternativeDescription(alternative: Alternative) {
  return `An evidence-led ${alternative.name} alternative guide for Mac: published product facts, workflow tradeoffs, and where Gojo fits.`
}

export function alternativeCanonical(alternative: Alternative) {
  return `${siteUrl}/alternatives/${alternative.slug}/`
}

export function alternativeArticleSchema(alternative: Alternative) {
  const title = alternativeTitle(alternative)
  const description = alternativeDescription(alternative)
  const canonical = alternativeCanonical(alternative)
  return {
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
          { "@type": "SoftwareApplication", name: alternative.name, url: alternative.officialUrl, operatingSystem: "macOS" },
        ],
        citation: [alternative.officialUrl, data.gojo.url],
      },
      {
        "@type": "FAQPage",
        mainEntity: [
          {
            "@type": "Question",
            name: `Is Gojo an alternative to ${alternative.name}?`,
            acceptedAnswer: { "@type": "Answer", text: `Yes, if you want ${alternative.gojoFit}. ${alternative.tradeoff}` },
          },
          {
            "@type": "Question",
            name: `Who should choose ${alternative.name}?`,
            acceptedAnswer: { "@type": "Answer", text: `${alternative.name} is best for ${alternative.bestFor}.` },
          },
        ],
      },
    ],
  }
}

export function alternativeArticleBody(alternative: Alternative) {
  const facts = alternative.officialFacts.map((fact) => `<li>${escapeHtml(fact)}</li>`).join("\n")
  return `<div class="article-top">${navigation()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Alternatives</a></nav><p class="article-label">Alternative guide</p><h1>${escapeHtml(alternative.name)} alternative: is Gojo a good fit for Mac?</h1><p class="article-summary">${escapeHtml(alternative.name)} is for ${escapeHtml(alternative.bestFor)}. Gojo is for ${escapeHtml(alternative.gojoFit)}.</p><div class="article-meta"><span>Updated ${data.updated}</span><span>Primary source checked</span></div></div></section></main></div>
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
  <section class="article-cta" aria-labelledby="try-gojo-title"><p class="answer-label">Want the focused option?</p><h2 id="try-gojo-title">Put daily Mac controls one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private on-device dictation</p></section>
  <section class="article-next"><p class="answer-label">Go deeper</p><h2>Compare the products directly</h2><p><a href="${alternative.relatedComparison}">Read Gojo vs ${escapeHtml(alternative.name)}</a> for a fuller workflow comparison, or return to the <a href="../">Gojo alternatives hub</a>.</p></section>
</article></main>`
}

export function alternativeHubSchema() {
  const canonical = `${siteUrl}/alternatives/`
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "CollectionPage",
        name: "Gojo alternatives for Mac",
        url: canonical,
        dateModified: data.updated,
        mainEntity: {
          "@type": "ItemList",
          numberOfItems: data.alternatives.length,
          itemListElement: data.alternatives.map((alternative, index) => ({
            "@type": "ListItem",
            position: index + 1,
            name: `${alternative.name} alternative guide`,
            url: `${canonical}${alternative.slug}/`,
          })),
        },
      },
    ],
  }
}

export function alternativeHubBody() {
  const cards = data.alternatives
    .map(
      (alternative) =>
        `<li><a class="alternative-card" href="${alternative.slug}/"><span>${escapeHtml(alternative.category)}</span><h3>${escapeHtml(alternative.name)}</h3><p>Best for ${escapeHtml(alternative.bestFor)}.</p><strong>Read the evidence-led guide <span aria-hidden="true">→</span></strong></a></li>`,
    )
    .join("\n")
  return `<div class="article-top">${navigation()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Alternatives</span></nav><p class="article-label">Mac utility alternatives</p><h1>Gojo alternatives for Mac: find the workflow that fits</h1><p class="article-summary">Compare focused notch utilities, broader productivity layers, and specialist Mac apps using published product facts—not a generic winner.</p><div class="article-meta"><span>Updated ${data.updated}</span><span>${data.alternatives.length} evidence-led guides</span></div></div></section></main></div>
<main class="article-main"><article class="article-body article-reader comparison-article"><div class="answer-box"><p class="answer-label">Short answer</p><p class="answer-copy">Gojo is the focused choice for private on-device dictation, windows, clipboard, files, media, and display controls in one MacBook-notch workspace. An alternative may fit better when you need deep automation, a dedicated specialist tool, extensive widgets, or a free open-source app.</p></div><h2>Browse Gojo alternatives by product fit</h2><p>Each guide links to the alternative’s official product page, separates published facts from editorial guidance, and explains where Gojo is the more cohesive option.</p><ol class="alternative-grid">${cards}</ol><h2>How to choose fairly</h2><ol><li><strong>Start with the repeated job.</strong> A dedicated window, clipboard, keyboard, or display tool can be better when it solves the one problem you have.</li><li><strong>Check the interaction model.</strong> Gojo favors a visible, hoverable notch surface. Some alternatives are keyboard-first, automation-first, or more widget-heavy.</li><li><strong>Verify current details before purchase.</strong> Features, system requirements, device limits, and pricing change. Every guide dates its primary-source check.</li></ol><section class="article-cta" aria-labelledby="hub-cta-title"><p class="answer-label">Prefer one cohesive utility?</p><h2 id="hub-cta-title">Try Gojo’s focused MacBook workspace.</h2><p>${escapeHtml(data.gojo.summary)}.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">${escapeHtml(data.gojo.trial)} &middot; Signed &amp; notarized</p></section></article></main>`
}

export function hubTitle() {
  return "Best Gojo alternatives for Mac in 2026"
}

export function hubDescription() {
  return "Compare Gojo alternatives for Mac by workflow, with official sources, dated facts, and clear guidance on where Gojo fits."
}

export function hubCanonical() {
  return `${siteUrl}/alternatives/`
}
