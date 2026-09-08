import featuresData from "@/content/features.json"
import { siteHeaderHtml } from "@/lib/site-header"

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

const featureVisuals: Record<string, { src: string; alt: string; caption: string }> = {
  "local-dictation": {
    src: "/screenshots/dictation-models.png",
    alt: "Gojo dictation model picker in the MacBook notch",
    caption: "Choose a local model, then speak into the app you are already using.",
  },
  "media-controls": {
    src: "/screenshots/media.png",
    alt: "Gojo media controls open beneath the MacBook notch",
    caption: "Playback stays close without floating over the rest of your work.",
  },
  "clipboard-history": {
    src: "/screenshots/clipboard.png",
    alt: "Gojo clipboard history in the MacBook notch",
    caption: "Recent text and images return in one glanceable strip.",
  },
  "window-controls": {
    src: "/screenshots/windows-tab.png",
    alt: "Gojo window switcher and layout controls",
    caption: "Preview, focus, and arrange windows from the same surface.",
  },
  "file-shelf": {
    src: "/screenshots/shelf.png",
    alt: "Files staged on Gojo's notch shelf",
    caption: "A temporary landing place for files moving between apps.",
  },
  "display-comfort": {
    src: "/screenshots/settings-nightshift.png",
    alt: "Gojo display comfort and Night Shift settings",
    caption: "Display comfort belongs beside the controls you already reach for.",
  },
}

function featureVisual(feature: Feature) {
  return featureVisuals[feature.slug]
}

const featureGuides: Record<string, { href: string; title: string; copy: string }> = {
  "local-dictation": {
    href: "/blog/best-local-dictation-apps-mac/",
    title: "Compare local dictation options for Mac",
    copy: "See where Apple Dictation, Voice Control, Gojo, and MacWhisper fit.",
  },
  "window-controls": {
    href: "/blog/best-window-tiling-apps-mac/",
    title: "Compare Mac window tiling tools",
    copy: "Start with built-in tiling, then compare dedicated managers and Gojo.",
  },
  "file-shelf": {
    href: "/blog/best-file-shelf-apps-mac/",
    title: "Compare file shelf apps for Mac",
    copy: "Choose between dedicated shelves and broader notch utilities.",
  },
}

function featureGuide(slug: string) {
  const guide = featureGuides[slug]
  if (!guide) return ""
  return `<section class="feature-workspace"><div><h2>${escapeHtml(guide.title)}</h2><p>${escapeHtml(guide.copy)}</p></div><a href="${guide.href}">Read the guide <span aria-hidden="true">→</span></a></section>`
}

function featureMotif(slug: string) {
  const motifs: Record<string, string> = {
    "local-dictation": `<svg viewBox="0 0 160 72"><g class="motif-bars">${[18,34,24,48,32,56,38,26,44,20].map((height, i) => `<rect x="${12 + i * 14}" y="${36 - height / 2}" width="5" height="${height}" rx="2.5" style="--i:${i}"/>`).join("")}</g></svg>`,
    "media-controls": `<svg viewBox="0 0 160 72"><path d="M16 46V26l18-8v36l-18-8Zm42-20v20M78 20v32M98 28v16M118 16v40M138 24v24"/><circle cx="58" cy="36" r="4"/></svg>`,
    "clipboard-history": `<svg viewBox="0 0 160 72"><rect x="48" y="10" width="70" height="48" rx="8"/><rect x="38" y="18" width="70" height="44" rx="8"/><path d="M54 32h36M54 42h26M54 52h31"/></svg>`,
    "window-controls": `<svg viewBox="0 0 160 72"><rect x="22" y="10" width="116" height="52" rx="8"/><path d="M22 25h116M80 25v37M28 18h2M36 18h2M44 18h2"/></svg>`,
    "file-shelf": `<svg viewBox="0 0 160 72"><path d="M18 50h124l-9 12H27L18 50Z"/><path class="motif-file" d="M62 8h28l14 14v27H62V8Zm28 0v14h14"/></svg>`,
    "display-comfort": `<svg viewBox="0 0 160 72"><circle cx="80" cy="36" r="17"/><path d="M80 7v10M80 55v10M51 36H41M119 36h-10M59 15l7 7M101 15l-7 7M59 57l7-7M101 57l-7-7"/></svg>`,
    calendar: `<svg viewBox="0 0 160 72"><rect x="38" y="9" width="84" height="54" rx="9"/><path d="M38 25h84M58 6v9M102 6v9M56 36h10M75 36h10M94 36h10M56 48h10M75 48h10"/></svg>`,
    "battery-status": `<svg viewBox="0 0 160 72"><rect x="28" y="18" width="96" height="38" rx="9"/><path d="M128 30h6v14h-6"/><rect class="motif-charge" x="35" y="25" width="64" height="24" rx="4"/></svg>`,
    "camera-mirror": `<svg viewBox="0 0 160 72"><rect x="32" y="13" width="96" height="46" rx="11"/><circle cx="80" cy="36" r="15"/><circle cx="80" cy="36" r="7"/><path d="M48 13l7-8h20l7 8"/></svg>`,
    shortcuts: `<svg viewBox="0 0 160 72"><rect x="16" y="14" width="128" height="44" rx="10"/><g class="motif-keys"><rect x="27" y="25" width="20" height="20" rx="4"/><rect x="55" y="25" width="20" height="20" rx="4"/><rect x="83" y="25" width="20" height="20" rx="4"/><rect x="111" y="25" width="20" height="20" rx="4"/></g></svg>`,
  }
  return `<div class="feature-motif" aria-hidden="true">${motifs[slug] ?? motifs.shortcuts}<span>Built into the notch</span></div>`
}

const nav = siteHeaderHtml

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
  const visual = featureVisual(feature)
  const media = visual
    ? `<figure class="feature-detail-visual" data-feature="${feature.slug}">${featureMotif(feature.slug)}<div class="feature-screen"><div class="feature-screen-notch" aria-hidden="true"></div><img src="${visual.src}" alt="${escapeHtml(visual.alt)}" width="1200" height="760"></div><figcaption>${escapeHtml(visual.caption)}</figcaption></figure>`
    : `<figure class="feature-detail-visual feature-detail-generated" data-feature="${feature.slug}">${featureMotif(feature.slug)}<div class="feature-detail-orbit" aria-hidden="true"><span>${escapeHtml(feature.name)}</span><i></i><i></i><i></i></div><figcaption>A glanceable part of Gojo’s MacBook-notch workspace.</figcaption></figure>`
  return `<div class="article-top feature-top feature-shell">${nav()}<main><section class="article-hero feature-detail-hero"><div class="wrap feature-detail-grid"><div class="feature-detail-copy"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Features</a></nav><h1>${escapeHtml(feature.name)}</h1><p class="article-summary">${escapeHtml(feature.tagline)}</p><div class="article-meta"><span>macOS 14+</span><span>Built into Gojo</span><span>One hover away</span></div></div>${media}</div></section></main></div><main class="article-main feature-detail-main"><article class="article-body article-reader feature-detail-body"><div class="answer-box"><p class="answer-label">What it does</p><p class="answer-copy">${escapeHtml(feature.what)}</p></div><div class="feature-story-grid"><section><h2>Why it is useful</h2><p>${escapeHtml(feature.useful)}</p></section><section><h2>Good to know</h2><p>${escapeHtml(feature.caveat)}</p></section></div><section class="feature-how"><div><h2>How ${escapeHtml(feature.name)} works in Gojo</h2><p>Three useful details, without a new app to manage.</p></div><ul class="source-facts">${details}</ul></section>${featureGuide(feature.slug)}<section class="feature-workspace"><div><h2>Part of one Mac workspace.</h2><p>${escapeHtml(feature.name)} lives beside media, windows, clipboard, files, display controls, and the other tools you reach for throughout the day.</p></div><a href="../">Explore every feature <span aria-hidden="true">→</span></a></section><section class="article-cta" aria-labelledby="try-gojo-title"><h2 id="try-gojo-title">Put ${escapeHtml(feature.name.toLowerCase())} one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private by design</p></section></article></main>`
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
  const bySlug = (slug: string) => data.features.find((feature) => feature.slug === slug)!
  const card = (slug: string, compact = false) => {
    const feature = bySlug(slug)
    const visual = featureVisual(feature)
    const image = visual
      ? `<div class="feature-card-media"><img src="${visual.src}" alt="" width="900" height="560"></div>`
      : `<div class="feature-card-signal" aria-hidden="true"><i></i><i></i><i></i></div>`
    return `<li><a class="feature-card${compact ? " feature-card-compact" : ""}" href="${feature.slug}/"><div class="feature-card-copy"><h3>${escapeHtml(feature.name)}</h3><p>${escapeHtml(feature.tagline)}</p><strong>Explore the workflow <span aria-hidden="true">↗</span></strong></div>${image}</a></li>`
  }
  const dictation = bySlug("local-dictation")
  const dictationVisual = featureVisual(dictation)!
  const movement = ["window-controls", "clipboard-history", "file-shelf"].map((slug) => card(slug)).join("")
  const awareness = ["media-controls", "display-comfort", "calendar"].map((slug) => card(slug)).join("")
  const utilities = ["battery-status", "camera-mirror", "shortcuts"].map((slug) => card(slug, true)).join("")
  const dock = data.features.slice(0, 6).map((feature) => `<span>${escapeHtml(feature.name.replace(" controls", "").replace(" history", ""))}</span>`).join("")
  return `<div class="article-top feature-hub-top feature-shell">${nav()}<main><section class="article-hero feature-hub-hero"><div class="wrap"><div class="feature-hero-heading"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Features</span></nav><h1>Your Mac’s busiest tools, gathered at the quietest edge.</h1></div><div class="feature-hero-context"><p class="article-summary">Dictate, move windows, retrieve a copy, stage a file, or change the soundtrack without opening another utility window.</p><div class="feature-hero-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Try Gojo free</a><a href="#feature-library">Explore all ${data.features.length} tools <span aria-hidden="true">↓</span></a></div></div><figure class="feature-live-stage"><div class="feature-live-bezel" aria-hidden="true"><span></span></div><img src="/screenshots/windows.png" alt="Gojo open at the MacBook notch, showing real window previews and snap controls" width="1322" height="418"><figcaption><strong>The actual Gojo notch.</strong><span>Live window previews, snap controls, and the rest of the workspace in one surface.</span></figcaption></figure><div class="feature-dock" aria-label="Gojo includes">${dock}</div></div></section></main></div><main class="article-main feature-hub-main"><article class="article-body article-reader feature-hub-body"><section class="feature-hub-intro"><div><h2>A whole workspace, not a stack of tiny apps.</h2></div><p>Gojo combines private on-device dictation, media, clipboard history, windows, file staging, display comfort, and glanceable tools in one native MacBook-notch workspace.</p></section><section id="feature-library" class="feature-library" aria-labelledby="feature-library-title"><div class="feature-library-head"><h2 id="feature-library-title">Everything the notch can do</h2><p>Choose the jobs that matter. Hide the rest.</p></div><a class="feature-spotlight" href="${dictation.slug}/"><div class="feature-spotlight-copy"><h3>Speak where the cursor already is.</h3><p>${escapeHtml(dictation.what)}</p><strong>Explore private dictation <span aria-hidden="true">↗</span></strong></div><div class="feature-spotlight-media"><img src="${dictationVisual.src}" alt="${escapeHtml(dictationVisual.alt)}" width="1200" height="760"></div></a><section class="feature-chapter"><header><h3>Move work without breaking stride.</h3><p>Arrange windows, recover a copy, or carry a file across apps without opening a separate workspace.</p></header><ol class="feature-chapter-grid">${movement}</ol></section><section class="feature-chapter feature-chapter-warm"><header><h3>Keep the Mac in view.</h3><p>Playback, display comfort, and the next commitment stay close without covering the work underneath.</p></header><ol class="feature-chapter-grid">${awareness}</ol></section><section class="feature-chapter feature-chapter-compact"><header><h3>Small checks. No new windows.</h3><p>Power, framing, and chosen shortcuts become glanceable parts of the same surface.</p></header><ol class="feature-chapter-grid">${utilities}</ol></section></section><section class="feature-privacy"><div class="feature-privacy-mark" aria-hidden="true"><span></span></div><div><h2>Dictation stays on your Mac.</h2><p>Recognition runs locally with explicit model choices. No API key, no cloud transcription, and no need to leave the text field you are already using.</p></div><a href="local-dictation/">See how local dictation works <span aria-hidden="true">→</span></a></section><section class="article-cta" aria-labelledby="features-cta"><h2 id="features-cta">Start with the tools you use most.</h2><p>Gojo gives you a fully unlocked three-day trial with no card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div></section></article></main>`
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
