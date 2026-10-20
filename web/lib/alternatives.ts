import alternativesData from "@/content/alternatives.json"
import { altMarkHtml } from "./alt-logos"
import { siteHeaderHtml } from "./site-header"

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

const navigation = siteHeaderHtml

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

function alternativesHero(bySlug: (slug: string) => Alternative): string {
  const groups = [
    { label: "Visible surfaces", slugs: ["droppy", "notchnook", "alcove"] },
    { label: "Information & launch", slugs: ["dynamiclake", "boring-notch", "raycast"] },
    { label: "Focused specialists", slugs: ["rectangle", "maccy", "alttab"] },
    { label: "System control", slugs: ["flux", "karabiner-elements", "bettertouchtool"] },
  ]
  let rowIndex = 0
  const index = groups
    .map((group) => {
      const rows = group.slugs
        .map((slug) => {
          const alternative = bySlug(slug)
          const row = rowIndex++
          return `<a class="alt-index-row" href="${alternative.slug}/" style="--row:${row}">${altMarkHtml(alternative.slug, alternative.name)}<span class="alt-index-copy"><strong>${escapeHtml(alternative.name)}</strong><small>${escapeHtml(alternative.category)}</small></span><span class="alt-index-arrow" aria-hidden="true">→</span></a>`
        })
        .join("")
      return `<section class="alt-index-group"><h2>${group.label}</h2><div>${rows}</div></section>`
    })
    .join("")

  return `<div class="article-top alternatives-hub-top alternative-shell page-frame">${navigation()}<main id="main-content" tabindex="-1"><section class="article-hero alternatives-hub-hero"><div class="wrap alternatives-hero-grid"><div class="alternatives-hero-copy"><p class="alternatives-kicker">Mac utilities · ${data.alternatives.length} compared</p><h1>Compare Mac utilities.</h1><p class="article-summary">Compare notch tools, launchers, window managers, clipboard apps, and automation by the work you need to do.</p><div class="alternatives-hero-actions"><a class="btn" href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="alternatives_hub_hero">Try Gojo free</a><a href="#alternatives-library">Compare all twelve <span aria-hidden="true">↓</span></a></div><p class="alternatives-hero-trust">Three days free · No account · macOS 14+</p></div><div class="alternatives-index" role="group" aria-label="Mac utilities by job">${index}</div></div></section>`
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
  const hero = alternativesHero(bySlug)
  return `${hero}
<div class="article-main alternatives-hub-main"><article class="article-body article-reader comparison-article alternatives-hub-body"><section class="alternatives-answer"><div><h2>Choose the interaction model before the feature list.</h2></div><p>Gojo combines private on-device dictation, windows, clipboard, files, media, and display controls in one MacBook-notch workspace. An alternative may fit better when you need deep automation, one specialist tool, extensive widgets, or a free open-source app.</p></section><section class="fit-spectrum" aria-label="Three kinds of Mac utility"><article><span>One surface</span><h3>Gojo</h3><p>Several everyday Mac jobs gathered at the notch.</p></article><article><span>One deep job</span><h3>Specialists</h3><p>Maximum depth for windows, clipboard, display, or keyboard.</p></article><article><span>Build your own</span><h3>Automation layers</h3><p>Keyboard-first commands and custom workflows.</p></article></section><section id="alternatives-library" class="alternatives-library" aria-labelledby="alternatives-library-title"><div class="alternatives-library-head"><div><h2 id="alternatives-library-title">Compare by product fit</h2><p>Official sources, dated checks, and the tradeoff up front.</p></div><a href="#how-to-choose">How we compare <span aria-hidden="true">↓</span></a></div><div class="alt-lanes"><section class="alt-lane alt-lane-notch"><header><h3>Notch &amp; island utilities</h3><p>For people who want a visible top-of-screen surface.</p></header><ol>${notchTools}</ol></section><section class="alt-lane alt-lane-specialists"><header><h3>Focused specialists</h3><p>For one repeated job that deserves dedicated depth.</p></header><ol>${specialists}</ol></section><section class="alt-lane alt-lane-power"><header><h3>Power layers</h3><p>For commands, extensions, and custom automation.</p></header><ol>${powerLayers}</ol></section></div></section><section id="how-to-choose" class="choose-fairly"><div><h2>How to choose fairly</h2></div><ol><li><strong>Start with the repeated job.</strong><span>A dedicated window, clipboard, keyboard, or display tool can be better when it solves the one problem you have.</span></li><li><strong>Check the interaction model.</strong><span>Gojo favors a visible, hoverable notch surface. Some alternatives are keyboard-first, automation-first, or more widget-heavy.</span></li><li><strong>Verify current details.</strong><span>Features, system requirements, device limits, and pricing change. Every guide dates its primary-source check.</span></li></ol></section><section class="article-cta" aria-labelledby="hub-cta-title"><p class="answer-label">Prefer one cohesive utility?</p><h2 id="hub-cta-title">Try Gojo’s MacBook workspace.</h2><p>${escapeHtml(data.gojo.summary)}.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="alternatives_hub_end">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">${escapeHtml(data.gojo.trial)} &middot; Signed &amp; notarized</p></section></article></div></main></div>`
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
