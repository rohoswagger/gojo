"use client"

import * as React from "react"
import { MenuIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"

type NavLink = { label: string; href: string }

/**
 * Site header. Sticky with a blurred, translucent ground so content passes
 * under it rather than colliding with it.
 */
function SiteNav({
  brand,
  brandHref = "/",
  links = [],
  action,
  className,
  ...props
}: React.ComponentProps<"header"> & {
  brand: React.ReactNode
  brandHref?: string
  links?: NavLink[]
  action?: { label: string; href: string }
}) {
  return (
    <header
      data-slot="site-nav"
      className={cn(
        "bg-background/80 border-border/60 sticky top-0 z-50 w-full border-b backdrop-blur-xl",
        className
      )}
      {...props}
    >
      <div className="mx-auto flex h-16 w-full max-w-[75rem] items-center justify-between gap-6 px-6 sm:px-8">
        <a href={brandHref} className="font-[family-name:var(--font-display)] text-[1.0625rem]">
          {brand}
        </a>

        <nav className="hidden items-center gap-8 md:flex">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="text-muted-foreground hover:text-foreground text-[0.875rem] transition-colors duration-(--duration-fast) ease-(--ease-swagui)"
            >
              {l.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          {action ? (
            <Button asChild size="sm" className="hidden md:inline-flex">
              <a href={action.href}>{action.label}</a>
            </Button>
          ) : null}

          <Sheet>
            <SheetTrigger asChild>
              <Button variant="ghost" size="icon" className="md:hidden" aria-label="Open menu">
                <MenuIcon />
              </Button>
            </SheetTrigger>
            <SheetContent side="right" className="w-72">
              <SheetHeader>
                <SheetTitle>{brand}</SheetTitle>
              </SheetHeader>
              <nav className="flex flex-col gap-1 px-4">
                {links.map((l) => (
                  <a
                    key={l.href}
                    href={l.href}
                    className="hover:bg-accent rounded-md px-3 py-2 text-[0.9375rem] transition-colors"
                  >
                    {l.label}
                  </a>
                ))}
              </nav>
              {action ? (
                <div className="mt-auto p-4">
                  <Button asChild className="w-full">
                    <a href={action.href}>{action.label}</a>
                  </Button>
                </div>
              ) : null}
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </header>
  )
}

export { SiteNav }
