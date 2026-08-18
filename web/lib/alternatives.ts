import alternativesData from "@/content/alternatives.json"
import { altMarkHtml } from "./alt-logos"

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
  return `<header class="site-header"><a class="brand" href="../../" aria-label="Gojo home"><svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"/></svg>Gojo</a><nav class="nav" aria-label="Primary"><a href="../../blog/">Blog</a><a href="../">Alternatives</a><a href="/downloads/">Download</a></nav></header>`
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

export function alternativeArticleBody(alternative: Alternative) {  const facts = alternative.officialFacts
    .map(
      (f, i) =>
        `<li><span class="spec-n">${String(i + 1).padStart(2, "0")}</span><span>${escapeHtml(f)}</span></li>`,
    )
    .join("")

  return `<div class="alt-shell">${navigation()}
<main class="alt-main">
  <div class="alt-wrap">
    <nav class="alt-crumb" aria-label="Breadcrumb"><a href="../../">Home</a><span aria-hidden="true">/</span><a href="../">Alternatives</a></nav>
    <h1 class="alt-h1">${escapeHtml(alternative.name)} <span class="alt-vs">vs</span> Gojo</h1>
    <p class="alt-lede">${escapeHtml(alternative.tradeoff)}</p>
    <p class="alt-stamp">Updated ${data.updated} <span aria-hidden="true">&middot;</span> Checked against the official ${escapeHtml(alternative.name)} site</p>

    <section class="alt-split" aria-label="Which one fits">
      <div class="alt-side">
        <p class="alt-side-name">${escapeHtml(alternative.name)}</p>
        <p class="alt-side-kind">${escapeHtml(alternative.category)}</p>
        <p class="alt-side-copy">Choose it for ${escapeHtml(alternative.bestFor)}.</p>
        <a class="alt-side-link" href="${escapeHtml(alternative.officialUrl)}" rel="external noopener">Official site</a>
      </div>
      <div class="alt-side alt-side-gojo">
        <p class="alt-side-name">Gojo</p>
        <p class="alt-side-kind">MacBook notch workspace</p>
        <p class="alt-side-copy">Choose it for ${escapeHtml(alternative.gojoFit)}.</p>
        <a class="alt-side-link" href="../../">See what it does</a>
      </div>
    </section>

    <section class="alt-block" aria-labelledby="facts">
      <h2 id="facts">What ${escapeHtml(alternative.name)} publishes</h2>
      <p class="alt-note">Taken from the developer's own product page on ${data.updated}. These describe the product, they do not score it.</p>
      <ol class="alt-specs">${facts}</ol>
    </section>

    <section class="alt-block" aria-labelledby="fit">
      <h2 id="fit">Side by side</h2>
      <dl class="alt-rows">
        <div><dt>Built for</dt><dd>${escapeHtml(alternative.bestFor)}</dd><dd class="alt-rows-gojo">${escapeHtml(alternative.gojoFit)}</dd></div>
        <div><dt>Shape</dt><dd>${escapeHtml(alternative.category)}</dd><dd class="alt-rows-gojo">Focused notch workspace</dd></div>
        <div><dt>Try it</dt><dd>Check the developer's current page</dd><dd class="alt-rows-gojo">${escapeHtml(data.gojo.trial)}</dd></div>
      </dl>
      <p class="alt-note">A specialist wins when its one job is where your day goes. Gojo wins when you would rather reach one surface than assemble several utilities.</p>
    </section>

    <section class="alt-block" aria-labelledby="faq">
      <h2 id="faq">Questions</h2>
      <div class="alt-faq">
        <h3>Is Gojo an alternative to ${escapeHtml(alternative.name)}?</h3>
        <p>Yes, when you want ${escapeHtml(alternative.gojoFit)}. ${escapeHtml(alternative.tradeoff)}</p>
        <h3>Who should choose ${escapeHtml(alternative.name)}?</h3>
        <p>${escapeHtml(alternative.name)} is best for ${escapeHtml(alternative.bestFor)}.</p>
      </div>
    </section>

    <section class="alt-cta" aria-labelledby="try-gojo-title">
      <h2 id="try-gojo-title">Try Gojo for three days.</h2>
      <p>Every feature unlocked. No account, no card.</p>
      <p class="alt-cta-actions">
        <a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Download for macOS</a>
        <a class="alt-cta-link" href="../../#buy">See pricing</a>
      </p>
      <p class="alt-fine">Signed and notarized <span aria-hidden="true">&middot;</span> macOS 14 or later <span aria-hidden="true">&middot;</span> Dictation runs on device</p>
    </section>

    <p class="alt-src">Primary source checked ${data.updated}: <a href="${escapeHtml(alternative.officialUrl)}" rel="external noopener">${escapeHtml(alternative.name)} official site</a>. Features, requirements and pricing change, so verify before buying. Read the longer <a href="${escapeHtml(alternative.relatedComparison)}">${escapeHtml(alternative.name)} comparison</a>.</p>
  </div>
</main>
</div>`
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
  const bySlug = (slug: string) => data.alternatives.find((alternative) => alternative.slug === slug)!
  const laneItem = (slug: string) => {
    const alternative = bySlug(slug)
    return `<li><a class="alt-lane-item" href="${alternative.slug}/"><div class="alt-lane-name">${altMarkHtml(alternative.slug, alternative.name)}<div><h3>${escapeHtml(alternative.name)}</h3><span>${escapeHtml(alternative.category)}</span></div></div><p>Best for ${escapeHtml(alternative.bestFor)}.</p><strong>Open guide <span aria-hidden="true">↗</span></strong></a></li>`
  }
  const notchTools = ["droppy", "notchnook", "alcove", "dynamiclake", "boring-notch"].map(laneItem).join("")
  const specialists = ["rectangle", "maccy", "alttab", "flux", "karabiner-elements"].map(laneItem).join("")
  const powerLayers = ["raycast", "bettertouchtool"].map(laneItem).join("")
  const constellation = data.alternatives.slice(0, 8).map((alternative, index) => `<span class="alt-orbit-mark alt-orbit-mark-${index + 1}" title="${escapeHtml(alternative.name)}">${altMarkHtml(alternative.slug, alternative.name, "alt-mark")}</span>`).join("")
  return `<div class="article-top alternatives-hub-top">${navigation()}<main><section class="article-hero alternatives-hub-hero"><div class="wrap alternatives-hero-grid"><div class="alternatives-hero-copy"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Alternatives</span></nav><h1>There is no best Mac utility. There is a best fit for your day.</h1><p class="article-summary">Compare notch tools, launchers, window managers, clipboard apps, and automation layers using dated product facts—not a generic winner.</p><div class="article-meta"><span>Updated ${data.updated}</span><span>${data.alternatives.length} evidence-led guides</span></div></div><div class="alternatives-orbit" aria-label="Mac utilities compared with Gojo"><div class="alt-orbit-rings" aria-hidden="true"></div>${constellation}<div class="alt-orbit-gojo"><svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"/></svg><span>Gojo</span></div></div></div></section></main></div>
<main class="article-main alternatives-hub-main"><article class="article-body article-reader comparison-article alternatives-hub-body"><section class="alternatives-answer"><div><h2>Choose the interaction model before the feature list.</h2></div><p>Gojo is the focused choice for private on-device dictation, windows, clipboard, files, media, and display controls in one MacBook-notch workspace. An alternative may fit better when you need deep automation, one specialist tool, extensive widgets, or a free open-source app.</p></section><section class="fit-spectrum" aria-label="Three kinds of Mac utility"><article><span>One surface</span><h3>Gojo</h3><p>Several everyday Mac jobs gathered at the notch.</p></article><article><span>One deep job</span><h3>Specialists</h3><p>Maximum depth for windows, clipboard, display, or keyboard.</p></article><article><span>Build your own</span><h3>Automation layers</h3><p>Keyboard-first commands and custom workflows.</p></article></section><section class="alternatives-library" aria-labelledby="alternatives-library-title"><div class="alternatives-library-head"><div><h2 id="alternatives-library-title">Compare by product fit</h2><p>Official sources, dated checks, and the tradeoff up front.</p></div><a href="#how-to-choose">How we compare <span aria-hidden="true">↓</span></a></div><div class="alt-lanes"><section class="alt-lane alt-lane-notch"><header><h3>Notch &amp; island utilities</h3><p>For people who want a visible top-of-screen surface.</p></header><ol>${notchTools}</ol></section><section class="alt-lane alt-lane-specialists"><header><h3>Focused specialists</h3><p>For one repeated job that deserves dedicated depth.</p></header><ol>${specialists}</ol></section><section class="alt-lane alt-lane-power"><header><h3>Power layers</h3><p>For commands, extensions, and custom automation.</p></header><ol>${powerLayers}</ol></section></div></section><section id="how-to-choose" class="choose-fairly"><div><h2>How to choose fairly</h2><p>A comparison is only useful when it helps you recognize your own working style.</p></div><ol><li><strong>Start with the repeated job.</strong><span>A dedicated window, clipboard, keyboard, or display tool can be better when it solves the one problem you have.</span></li><li><strong>Check the interaction model.</strong><span>Gojo favors a visible, hoverable notch surface. Some alternatives are keyboard-first, automation-first, or more widget-heavy.</span></li><li><strong>Verify current details.</strong><span>Features, system requirements, device limits, and pricing change. Every guide dates its primary-source check.</span></li></ol></section><section class="article-cta" aria-labelledby="hub-cta-title"><p class="answer-label">Prefer one cohesive utility?</p><h2 id="hub-cta-title">Try Gojo’s focused MacBook workspace.</h2><p>${escapeHtml(data.gojo.summary)}.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">${escapeHtml(data.gojo.trial)} &middot; Signed &amp; notarized</p></section></article></main>`
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
