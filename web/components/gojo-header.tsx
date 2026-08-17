import Link from "next/link"

import { GojoLogo } from "@/components/gojo-logo"

const LINKS = [
  { href: "/features/", label: "Features" },
  { href: "/blog/", label: "Blog" },
  { href: "/alternatives/", label: "Alternatives" },
  { href: "/downloads/", label: "Download" },
]

/**
 * The site header. Markup mirrors what lib/features.ts and lib/alternatives.ts
 * emit as HTML strings, so both rendering paths land on the same `.site-header`
 * rules in app/skin.css.
 */
export function GojoHeader({ links = LINKS }: { links?: { href: string; label: string }[] }) {
  return (
    <header className="site-header">
      <Link className="brand" href="/" aria-label="Gojo home">
        <GojoLogo />
        Gojo
      </Link>
      <nav className="nav" aria-label="Primary">
        {links.map((link) => (
          <Link key={link.href} className="ghost-link" href={link.href}>
            {link.label}
          </Link>
        ))}
      </nav>
    </header>
  )
}
