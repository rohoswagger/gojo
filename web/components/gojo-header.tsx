import Link from "next/link"

import { GojoLogo } from "@/components/gojo-logo"
import { DOWNLOAD_LINK, getHeaderLinks, type HeaderLink } from "@/lib/site-header"

/**
 * The site header: a floating bar that sits on the page ground rather than
 * spanning it. Markup mirrors what lib/site-header.ts emits as an HTML string
 * for /features/* and /alternatives/*, so both rendering paths land on the
 * same `.site-header` rules in app/skin.css.
 *
 * `active` marks the current section so its link takes the filled pill. It is
 * matched against each link's href prefix, which is why it is a path and not a
 * name — the HTML-string path can pass the same value.
 */
export function GojoHeader({
  links,
  overlay = false,
  home = false,
  active,
}: {
  links?: HeaderLink[]
  overlay?: boolean
  home?: boolean
  active?: string
}) {
  const resolvedLinks = links ?? getHeaderLinks(home)
  return (
    <header className={`site-header${overlay ? " site-header-overlay" : ""}`}>
      <Link className="brand" href="/" aria-label="Gojo home">
        <GojoLogo />
        Gojo
      </Link>
      <nav className="nav" aria-label="Primary">
        {resolvedLinks.map((link) => {
          const current = active !== undefined && link.href === active
          return (
            <Link
              key={link.href}
              className={`ghost-link${current ? " is-current" : ""}`}
              href={link.href}
              aria-current={current ? "page" : undefined}
            >
              {link.label}
            </Link>
          )
        })}
      </nav>
      <Link className="btn btn-primary nav-cta" href={DOWNLOAD_LINK.href}>
        {DOWNLOAD_LINK.label}
        <span className="nav-cta-arrow" aria-hidden="true">
          &rarr;
        </span>
      </Link>
    </header>
  )
}
