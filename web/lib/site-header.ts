export const GOJO_LOGO_PATH =
  "M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"

export type HeaderLink = { href: string; label: string }
export const DOWNLOAD_LINK: HeaderLink = { href: "/downloads/", label: "Download" }

const HEADER_ITEMS = [
  { label: "Features", href: "/features/", homeHref: "#features" },
  { label: "Pricing", href: "/#buy", homeHref: "#buy" },
  { label: "Blog", href: "/blog/", homeHref: "/blog/" },
] as const

export function getHeaderLinks(home = false): HeaderLink[] {
  return HEADER_ITEMS.map((item) => ({
    label: item.label,
    href: home ? item.homeHref : item.href,
  }))
}

export function siteHeaderHtml(active?: string): string {
  const links = getHeaderLinks()
    .map((link) => {
      const current = active !== undefined && link.href === active
      const cls = current ? "ghost-link is-current" : "ghost-link"
      const aria = current ? ' aria-current="page"' : ""
      return `<a class="${cls}" href="${link.href}"${aria}>${link.label}</a>`
    })
    .join("")
  return `<header class="site-header site-header-overlay"><a class="brand" href="/" aria-label="Gojo home"><svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="${GOJO_LOGO_PATH}"/></svg>Gojo</a><nav class="nav" aria-label="Primary">${links}</nav><a class="btn btn-primary nav-cta" href="${DOWNLOAD_LINK.href}">${DOWNLOAD_LINK.label}<span class="nav-cta-arrow" aria-hidden="true">&rarr;</span></a></header>`
}
