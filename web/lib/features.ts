import featuresData from "@/content/features.json"
import { siteHeaderHtml } from "@/lib/site-header"

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

const featureVisuals: Partial<Record<string, { src: string; width: number; height: number; alt: string; caption: string }>> = {
  "local-dictation": {
    src: "/screenshots/dictation-models.png",
    width: 920,
    height: 342,
    alt: "Gojo dictation model picker in the MacBook notch",
    caption: "Choose a local model, then speak into the app you are already using.",
  },
  "media-controls": {
    src: "/screenshots/media.png",
    width: 1308,
    height: 392,
    alt: "Gojo media controls open beneath the MacBook notch",
    caption: "Playback stays close without floating over the rest of your work.",
  },
  "clipboard-history": {
    src: "/screenshots/clipboard.png",
    width: 1388,
    height: 394,
    alt: "Gojo clipboard history in the MacBook notch",
    caption: "Recent text and images return in one glanceable strip.",
  },
  "window-controls": {
    src: "/screenshots/windows.png",
    width: 1322,
    height: 418,
    alt: "Gojo window controls showing app choices, snap layouts, and keyboard shortcuts",
    caption: "App choices, snap controls, and shortcut labels in Gojo’s Windows tab.",
  },
  "file-shelf": {
    src: "/screenshots/shelf.png",
    width: 1298,
    height: 392,
    alt: "Files staged on Gojo's notch shelf",
    caption: "A temporary landing place for files moving between apps.",
  },
  "display-comfort": {
    src: "/screenshots/settings-nightshift.png",
    width: 1362,
    height: 1178,
    alt: "Gojo display comfort and Night Shift settings",
    caption: "Night Shift and display comfort settings in Gojo.",
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
    ? `<figure class="feature-detail-visual" data-feature="${feature.slug}"><div class="feature-screen"><div class="feature-screen-notch" aria-hidden="true"></div><img src="${visual.src}" alt="${escapeHtml(visual.alt)}" width="${visual.width}" height="${visual.height}"></div><figcaption>${escapeHtml(visual.caption)}</figcaption></figure>`
    : `<div class="feature-detail-description"><p>${escapeHtml(feature.what)}</p><a href="../#feature-library">Explore the full workspace <span aria-hidden="true">→</span></a></div>`
  return `<div class="article-top feature-top feature-shell page-frame">${nav()}<main id="main-content" tabindex="-1"><section class="article-hero feature-detail-hero"><div class="wrap feature-detail-grid"><div class="feature-detail-copy"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../../">Home</a><span>/</span><a href="../">Features</a></nav><h1>${escapeHtml(feature.name)}</h1><p class="article-summary">${escapeHtml(feature.tagline)}</p><div class="article-meta"><span>macOS 14+</span><span>Built into Gojo</span><span>One hover away</span></div></div>${media}</div></section><div class="article-main feature-detail-main"><article class="article-body article-reader feature-detail-body">${visual ? `<div class="answer-box"><p class="answer-label">What it does</p><p class="answer-copy">${escapeHtml(feature.what)}</p></div>` : ""}<div class="feature-story-grid"><section><h2>Why it is useful</h2><p>${escapeHtml(feature.useful)}</p></section><section><h2>Good to know</h2><p>${escapeHtml(feature.caveat)}</p></section></div><section class="feature-how"><div><h2>How ${escapeHtml(feature.name)} works in Gojo</h2></div><ul class="source-facts">${details}</ul></section>${featureGuide(feature.slug)}<section class="article-cta" aria-labelledby="try-gojo-title"><h2 id="try-gojo-title">Put ${escapeHtml(feature.name.toLowerCase())} one hover away.</h2><p>Try every Gojo feature free for three days. No account or card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="feature_detail_end">Start your free trial</a><a class="article-cta-link" href="../../#buy">Compare monthly and lifetime</a></div><p class="article-cta-trust">Signed &amp; notarized &middot; macOS 14+ &middot; private by design</p></section></article></div></main></div>`
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
      ? `<div class="feature-card-media"><img src="${visual.src}" alt="" width="${visual.width}" height="${visual.height}"></div>`
      : ""
    return `<li><a class="feature-card${compact ? " feature-card-compact" : ""}" href="${feature.slug}/"><div class="feature-card-copy"><h3>${escapeHtml(feature.name)}</h3><p>${escapeHtml(feature.tagline)}</p><strong>Explore the workflow <span aria-hidden="true">↗</span></strong></div>${image}</a></li>`
  }
  const dictation = bySlug("local-dictation")
  const dictationVisual = featureVisual(dictation)!
  const movement = ["window-controls", "clipboard-history", "file-shelf"].map((slug) => card(slug)).join("")
  const awareness = ["media-controls", "display-comfort", "calendar"].map((slug) => card(slug)).join("")
  const utilities = ["battery-status", "camera-mirror", "shortcuts"].map((slug) => card(slug, true)).join("")
  const dock = data.features.slice(0, 6).map((feature) => `<span>${escapeHtml(feature.name.replace(" controls", "").replace(" history", ""))}</span>`).join("")
  return `<div class="article-top feature-hub-top feature-shell page-frame">${nav()}<main id="main-content" tabindex="-1"><section class="article-hero feature-hub-hero"><div class="wrap"><div class="feature-hero-heading"><nav class="breadcrumb" aria-label="Breadcrumb"><a href="../">Home</a><span>/</span><span>Features</span></nav><h1>Your Mac tools, one hover away.</h1></div><div class="feature-hero-context"><p class="article-summary">Dictate, move windows, retrieve a copy, stage a file, or change the soundtrack without opening another utility window.</p><div class="feature-hero-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="feature_hub_hero">Try Gojo free</a><a href="#feature-library">Explore all ${data.features.length} tools <span aria-hidden="true">↓</span></a></div></div><figure class="feature-live-stage"><div class="feature-live-bezel" aria-hidden="true"><span></span></div><img src="/screenshots/windows.png" alt="Gojo Windows tab showing app choices, snap controls, and keyboard shortcuts" width="1322" height="418"><figcaption><strong>The actual Gojo notch.</strong><span>App choices, snap controls, and shortcut labels in the Windows tab.</span></figcaption></figure><div class="feature-dock" role="group" aria-label="Gojo includes">${dock}</div></div></section><div class="article-main feature-hub-main"><article class="article-body article-reader feature-hub-body"><section class="feature-hub-intro"><div><h2>Your daily Mac tools at the notch.</h2></div><p>Gojo combines private on-device dictation, media, clipboard history, windows, file staging, display comfort, and glanceable tools in one native MacBook-notch workspace.</p></section><section id="feature-library" class="feature-library" aria-labelledby="feature-library-title"><div class="feature-library-head"><h2 id="feature-library-title">Everything the notch can do</h2><p>Choose the jobs that matter. Hide the rest.</p></div><a class="feature-spotlight" href="${dictation.slug}/"><div class="feature-spotlight-copy"><h3>Speak where the cursor already is.</h3><p>${escapeHtml(dictation.what)}</p><strong>Explore private dictation <span aria-hidden="true">↗</span></strong></div><div class="feature-spotlight-media"><img src="${dictationVisual.src}" alt="${escapeHtml(dictationVisual.alt)}" width="${dictationVisual.width}" height="${dictationVisual.height}"></div></a><section class="feature-chapter"><header><h3>Move work without breaking stride.</h3><p>Arrange windows, recover a copy, or carry a file across apps without opening a separate workspace.</p></header><ol class="feature-chapter-grid">${movement}</ol></section><section class="feature-chapter feature-chapter-warm"><header><h3>Keep the Mac in view.</h3><p>Playback, display comfort, and the next commitment stay close without covering the work underneath.</p></header><ol class="feature-chapter-grid">${awareness}</ol></section><section class="feature-chapter feature-chapter-compact"><header><h3>Small checks. No new windows.</h3><p>Power, framing, and chosen shortcuts become glanceable parts of the same surface.</p></header><ol class="feature-chapter-grid">${utilities}</ol></section></section><section class="feature-privacy"><div class="feature-privacy-mark" aria-hidden="true"><span></span></div><div><h2>Local dictation stays on your Mac.</h2><p>Recognition runs locally with explicit model choices. No API key, no cloud transcription, and no need to leave the text field you are already using.</p></div><a href="local-dictation/">See how local dictation works <span aria-hidden="true">→</span></a></section><section class="article-cta" aria-labelledby="features-cta"><h2 id="features-cta">Start with the tools you use most.</h2><p>Gojo gives you a fully unlocked three-day trial with no card required.</p><div class="article-cta-actions"><a class="btn btn-primary" href="https://downloads.trygojo.com/Gojo.dmg" data-funnel-event="download_cta_clicked" data-funnel-placement="feature_hub_end">Start your free trial</a><a class="article-cta-link" href="../#buy">Compare monthly and lifetime</a></div></section></article></div></main></div>`
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
