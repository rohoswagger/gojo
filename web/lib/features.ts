import featuresData from "@/content/features.json"

// Ported from gojo/scripts/generate-feature-pages.mjs. See lib/alternatives.ts
// for the porting rationale (structure/copy kept verbatim; <head> concerns
// moved to Next's Metadata API; internal relative links left as-is since
// route depth matches the original static export).

export type Feature = {
  slug: string
  name: string
  tagline: string
  what: string
  useful: string
  details: string[]
  caveat: string
  related: string
}

type FeaturesData = {
  updated: string
  features: Feature[]
}

const data = featuresData as FeaturesData
export const siteUrl = "https://trygojo.com"

export const escapeHtml = (value: unknown) =>
  String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;")

export function getFeatures(): Feature[] {
  return data.features
}

export function getFeature(slug: string): Feature | undefined {
  return data.features.find((feature) => feature.slug === slug)
}

export function getFeaturesUpdated(): string {
  return data.updated
}

const nav = () =>
  `<header class="site-header"><a class="brand" href="../../" aria-label="Gojo home">Gojo</a><nav class="nav" aria-label="Primary"><a href="../">Features</a><a href="../../blog/">Blog</a><a href="../../alternatives/">Alternatives</a><a href="/downloads/">Download</a></nav></header>`

export function featureTitle(feature: Feature) {
  return `${feature.name} for MacBook notch | Gojo`
}

export function featureDescription(feature: Feature) {
  return `${feature.what} Learn how Gojo's ${feature.name.toLowerCase()} is useful on a MacBook.`
}

export function featureCanonical(feature: Feature) {
  return `${siteUrl}/features/${feature.slug}/`
}

export function featureArticleSchema(feature: Feature) {
  const title = featureTitle(feature)
  const description = featureDescription(feature)
  const canonical = featureCanonical(feature)
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
        about: { "@type": "SoftwareApplication", name: "Gojo", operatingSystem: "macOS 14+", url: siteUrl },
      },
      {
        "@type": "FAQPage",
        mainEntity: [
          { "@type": "Question", name: `What is Gojo ${feature.name}?`, acceptedAnswer: { "@type": "Answer", text: feature.what } },
          { "@type": "Question", name: `Why use Gojo ${feature.name}?`, acceptedAnswer: { "@type": "Answer", text: feature.useful } },
        ],
      },
    ],
  }
}

export function featureArticleBody(feature: Feature) {
  const details = feature.details.map((detail) => `<li>${escapeHtml(detail)}</li>`).join("")
  return `<div class="article-top">${nav()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Features</a></nav><p class="article-label">Gojo feature</p><h1>${escapeHtml(feature.name)}</h1><p class="article-summary">${escapeHtml(feature.tagline)}</p><div class="article-meta"><span>Updated ${data.updated}</span><span>macOS 14+</span></div></div></section></main></div><main class="article-main"><article class="article-body article-reader"><div class="answer-box"><p class="answer-label">What it does</p><p class="answer-copy">${escapeHtml(feature.what)}</p></div><h2>Why it is useful</h2><p>${escapeHtml(feature.useful)}</p><h2>How ${escapeHtml(feature.name)} works in Gojo</h2><ul class="source-facts">${details}</ul><h2>Good to know</h2><p>${escapeHtml(feature.caveat)}</p><h2>One workspace, not another standalone utility</h2><p>${escapeHtml(feature.name)} is one part of Gojo’s MacBook-notch workspace. Keep the tools you use visible, hide the rest, and reach media, windows, clipboard, files, display controls, and more from the same native surface.</p><h2>Related Gojo feature</h2><p><a href="${feature.related}">See the relevant Gojo product detail</a>, or browse the <a href="../">complete feature library</a>.</p><section class="article-cta" aria-labelledby="try-gojo-title"><p class="answer-label">Try it on your Mac</p><h2 id="try-gojo-title">Put ${escapeHtml(feature.name.toLowerCase())} one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private by design</p></section></article></main>`
}

export function hubSchema() {
  const canonical = `${siteUrl}/features/`
  return {
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    name: "Gojo features",
    url: canonical,
    dateModified: data.updated,
    mainEntity: {
      "@type": "ItemList",
      numberOfItems: data.features.length,
      itemListElement: data.features.map((feature, index) => ({
        "@type": "ListItem",
        position: index + 1,
        name: feature.name,
        url: `${canonical}${feature.slug}/`,
      })),
    },
  }
}

export function hubBody() {
  const cards = data.features
    .map(
      (feature) =>
        `<li><a class="alternative-card" href="${feature.slug}/"><span>Gojo feature</span><h3>${escapeHtml(feature.name)}</h3><p>${escapeHtml(feature.tagline)}</p><strong>See how it works <span aria-hidden="true">→</span></strong></a></li>`,
    )
    .join("")
  return `<div class="article-top">${nav()}<main><section class="article-hero"><div class="wrap"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Features</span></nav><p class="article-label">Gojo features</p><h1>MacBook-notch tools for the jobs you repeat every day</h1><p class="article-summary">Each Gojo feature is built to keep a useful Mac control close without turning your menu bar into a stack of separate utilities.</p><div class="article-meta"><span>Updated ${data.updated}</span><span>${data.features.length} feature guides</span></div></div></section></main></div><main class="article-main"><article class="article-body article-reader"><div class="answer-box"><p class="answer-label">What Gojo does</p><p class="answer-copy">Gojo combines private on-device dictation, media, clipboard history, windows, file staging, display comfort, and glanceable tools in one native MacBook-notch workspace.</p></div><h2>Explore every Gojo feature</h2><ol class="alternative-grid">${cards}</ol><section class="article-cta" aria-labelledby="features-cta"><p class="answer-label">Ready to try the workspace?</p><h2 id="features-cta">Start with the tools you use most.</h2><p>Gojo gives you a fully unlocked three-day trial with no card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div></section></article></main>`
}

export function hubTitle() {
  return "Gojo features: MacBook-notch productivity tools"
}

export function hubDescription() {
  return "Explore Gojo's MacBook-notch features: private dictation, media, clipboard, windows, files, display controls, calendar, battery, camera mirror, and shortcuts."
}

export function hubCanonical() {
  return `${siteUrl}/features/`
}
