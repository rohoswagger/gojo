import featuresData from "@/content/features.json"
import alternativesData from "@/content/alternatives.json"

import { GojoLogo } from "@/components/gojo-logo"
import { SiteFooter } from "@/components/site-footer"

/**
 * The one site footer. Replaces both `site-footer-legacy` and the copy that
 * was inlined in app/page.tsx — the sitemap columns are derived from the same
 * content files that generate /features/* and /alternatives/*, so a new entry
 * shows up here without a second edit.
 */
export function GojoFooter() {
  const columns = [
    {
      title: "Features",
      links: featuresData.features.map((feature) => ({
        href: `/features/${feature.slug}/`,
        label: feature.name,
      })),
    },
    {
      title: "Alternatives",
      links: alternativesData.alternatives.map((alternative) => ({
        href: `/alternatives/${alternative.slug}/`,
        label: `${alternative.name} alternative`,
      })),
    },
    {
      title: "Gojo",
      links: [
        { href: "/", label: "Home" },
        { href: "/#features", label: "How it works" },
        { href: "/#buy", label: "Pricing" },
        { href: "/blog/", label: "Blog" },
        { href: "/downloads/", label: "Download for macOS" },
        { href: "https://github.com/rohoswagger/gojo", label: "GitHub" },
      ],
    },
  ]

  return (
    <SiteFooter
      brand={
        <span className="inline-flex items-center gap-2">
          <GojoLogo className="w-[1.25rem]" />
          Gojo
        </span>
      }
      tagline="Dictation, windows, clipboard, files, media and display controls — one hover from your MacBook notch."
      columns={columns}
      bottom={
        <>
          <span>&copy; 2026 Gojo</span>
          <span>Signed &amp; notarized &middot; macOS 14+</span>
        </>
      }
    />
  )
}
