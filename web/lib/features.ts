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

const nav = () =>
  `<header class="site-header"><a class="brand" href="../../" aria-label="Gojo home"><svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"/></svg>Gojo</a><nav class="nav" aria-label="Primary"><a href="../">Features</a><a href="../../blog/">Blog</a><a href="../../alternatives/">Alternatives</a><a href="/downloads/">Download</a></nav></header>`

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
    ? `<figure class="feature-detail-visual"><div class="feature-screen"><img src="${visual.src}" alt="${escapeHtml(visual.alt)}" width="1200" height="760"></div><figcaption>${escapeHtml(visual.caption)}</figcaption></figure>`
    : `<div class="feature-detail-orbit" aria-hidden="true"><span>${escapeHtml(feature.name)}</span><i></i><i></i><i></i></div>`
  return `<div class="article-top feature-top">${nav()}<main><section class="article-hero feature-detail-hero"><div class="wrap feature-detail-grid"><div class="feature-detail-copy"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Features</a></nav><h1>${escapeHtml(feature.name)}</h1><p class="article-summary">${escapeHtml(feature.tagline)}</p><div class="article-meta"><span>Updated ${data.updated}</span><span>macOS 14+</span><span>Built into Gojo</span></div></div>${media}</div></section></main></div><main class="article-main feature-detail-main"><article class="article-body article-reader feature-detail-body"><div class="answer-box"><p class="answer-label">What it does</p><p class="answer-copy">${escapeHtml(feature.what)}</p></div><div class="feature-story-grid"><section><h2>Why it is useful</h2><p>${escapeHtml(feature.useful)}</p></section><section><h2>Good to know</h2><p>${escapeHtml(feature.caveat)}</p></section></div><section class="feature-how"><div><h2>How ${escapeHtml(feature.name)} works in Gojo</h2></div><ul class="source-facts">${details}</ul></section><section class="feature-workspace"><div><h2>One workspace, not another standalone utility</h2><p>${escapeHtml(feature.name)} is one part of Gojo’s MacBook-notch workspace. Keep the tools you use visible, hide the rest, and reach media, windows, clipboard, files, display controls, and more from the same native surface.</p></div><a href="${feature.related}">See the related product detail <span aria-hidden="true">→</span></a></section><section class="article-cta" aria-labelledby="try-gojo-title"><p class="answer-label">Try it on your Mac</p><h2 id="try-gojo-title">Put ${escapeHtml(feature.name.toLowerCase())} one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private by design</p></section></article></main>`
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
  return `<div class="article-top feature-hub-top">${nav()}<main><section class="article-hero feature-hub-hero"><div class="wrap"><div class="feature-hero-heading"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Features</span></nav><h1>Your Mac’s busiest tools, gathered at the quietest edge.</h1></div><div class="feature-hero-context"><p class="article-summary">Dictate, move windows, retrieve a copy, stage a file, or change the soundtrack without opening another utility window.</p><div class="feature-hero-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Try Gojo free</a><a href="#feature-library">Explore all ${data.features.length} tools <span aria-hidden="true">↓</span></a></div></div><figure class="feature-live-stage"><div class="feature-live-bezel" aria-hidden="true"><span></span></div><img src="/screenshots/windows.png" alt="Gojo open at the MacBook notch, showing real window previews and snap controls" width="1322" height="418"><figcaption><strong>The actual Gojo notch.</strong><span>Live window previews, snap controls, and the rest of the workspace in one surface.</span></figcaption></figure><div class="feature-dock" aria-label="Gojo includes">${dock}</div></div></section></main></div><main class="article-main feature-hub-main"><article class="article-body article-reader feature-hub-body"><section class="feature-hub-intro"><div><h2>A whole workspace, not a stack of tiny apps.</h2></div><p>Gojo combines private on-device dictation, media, clipboard history, windows, file staging, display comfort, and glanceable tools in one native MacBook-notch workspace.</p></section><section id="feature-library" class="feature-library" aria-labelledby="feature-library-title"><div class="feature-library-head"><h2 id="feature-library-title">Everything the notch can do</h2><p>Choose the jobs that matter. Hide the rest.</p></div><a class="feature-spotlight" href="${dictation.slug}/"><div class="feature-spotlight-copy"><h3>Speak where the cursor already is.</h3><p>${escapeHtml(dictation.what)}</p><strong>Explore private dictation <span aria-hidden="true">↗</span></strong></div><div class="feature-spotlight-media"><img src="${dictationVisual.src}" alt="${escapeHtml(dictationVisual.alt)}" width="1200" height="760"></div></a><section class="feature-chapter"><header><h3>Move work without breaking stride.</h3><p>Arrange windows, recover a copy, or carry a file across apps without opening a separate workspace.</p></header><ol class="feature-chapter-grid">${movement}</ol></section><section class="feature-chapter feature-chapter-warm"><header><h3>Keep the Mac in view.</h3><p>Playback, display comfort, and the next commitment stay close without covering the work underneath.</p></header><ol class="feature-chapter-grid">${awareness}</ol></section><section class="feature-chapter feature-chapter-compact"><header><h3>Small checks. No new windows.</h3><p>Power, framing, and chosen shortcuts become glanceable parts of the same surface.</p></header><ol class="feature-chapter-grid">${utilities}</ol></section></section><section class="feature-privacy"><div class="feature-privacy-mark" aria-hidden="true"><span></span></div><div><h2>Dictation stays on your Mac.</h2><p>Recognition runs locally with explicit model choices. No API key, no cloud transcription, and no need to leave the text field you are already using.</p></div><a href="local-dictation/">See how local dictation works <span aria-hidden="true">→</span></a></section><section class="article-cta" aria-labelledby="features-cta"><h2 id="features-cta">Start with the tools you use most.</h2><p>Gojo gives you a fully unlocked three-day trial with no card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div></section></article></main>`
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
