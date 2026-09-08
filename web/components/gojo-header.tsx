import Link from "next/link"

import { GojoLogo } from "@/components/gojo-logo"
import { DOWNLOAD_LINK, getHeaderLinks, type HeaderLink } from "@/lib/site-header"

/**
 * The site header. Markup mirrors what lib/features.ts and lib/alternatives.ts
 * emit as HTML strings, so both rendering paths land on the same `.site-header`
 * rules in app/skin.css.
 */
export function GojoHeader({
  links,
  overlay = false,
  home = false,
}: {
  links?: HeaderLink[]
  overlay?: boolean
  home?: boolean
}) {
  const resolvedLinks = links ?? getHeaderLinks(home)
  return (
    <header className={`site-header${overlay ? " site-header-overlay" : ""}`}>
      <Link className="brand" href="/" aria-label="Gojo home">
        <GojoLogo />
        Gojo
      </Link>
      <nav className="nav" aria-label="Primary">
        {resolvedLinks.map((link) => (
          <Link key={link.href} className="ghost-link" href={link.href}>
            {link.label}
          </Link>
        ))}
        {!overlay ? (
          <Link className="ghost-link" href={DOWNLOAD_LINK.href}>
            {DOWNLOAD_LINK.label}
          </Link>
        ) : null}
      </nav>
      {overlay ? (
        <Link className="btn btn-primary nav-cta" href={DOWNLOAD_LINK.href}>
          {DOWNLOAD_LINK.label}
        </Link>
      ) : null}
    </header>
  )
}
