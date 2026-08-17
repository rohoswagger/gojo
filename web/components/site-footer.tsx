import * as React from "react"

import { cn } from "@/lib/utils"

type FooterColumn = { title: string; links: { label: string; href: string }[] }

function SiteFooter({
  brand,
  tagline,
  columns = [],
  bottom,
  className,
  ...props
}: React.ComponentProps<"footer"> & {
  brand: React.ReactNode
  tagline?: React.ReactNode
  columns?: FooterColumn[]
  bottom?: React.ReactNode
}) {
  return (
    <footer
      data-slot="site-footer"
      className={cn("border-border/60 w-full border-t px-6 pt-20 pb-10 sm:px-8", className)}
      {...props}
    >
      <div className="mx-auto w-full max-w-[75rem]">
        <div className="grid gap-12 sm:grid-cols-2 lg:grid-cols-[1.5fr_repeat(3,1fr)]">
          <div>
            <p className="font-[family-name:var(--font-display)] text-[1.125rem]">{brand}</p>
            {tagline ? (
              <p className="text-muted-foreground mt-3 max-w-[34ch] text-[0.9375rem] leading-[1.6]">
                {tagline}
              </p>
            ) : null}
          </div>

          {columns.map((col) => (
            <div key={col.title}>
              <p className="text-muted-foreground mb-4 font-mono text-[0.625rem] tracking-[0.22em] uppercase">
                {col.title}
              </p>
              <ul className="flex flex-col gap-2.5">
                {col.links.map((l) => (
                  <li key={l.href}>
                    <a
                      href={l.href}
                      className="text-muted-foreground hover:text-foreground text-[0.9375rem] transition-colors duration-(--duration-fast) ease-(--ease-swagui)"
                    >
                      {l.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="border-border/60 text-muted-foreground mt-16 flex flex-wrap items-center justify-between gap-4 border-t pt-8 text-[0.8125rem]">
          {bottom}
        </div>
      </div>
    </footer>
  )
}

export { SiteFooter }
