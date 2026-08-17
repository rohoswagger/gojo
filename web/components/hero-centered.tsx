import * as React from "react"
import { ArrowRightIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Reveal } from "@/components/reveal"

/**
 * Centred hero. Display type runs to a deliberately tight measure — roughly
 * two or three words a line — which is what makes large headings read as
 * composed rather than merely big.
 */
function HeroCentered({
  eyebrow,
  title,
  description,
  primaryAction,
  secondaryAction,
  status,
  className,
  ...props
}: Omit<React.ComponentProps<"section">, "title"> & {
  eyebrow?: React.ReactNode
  title: React.ReactNode
  description?: React.ReactNode
  primaryAction?: { label: string; href: string }
  secondaryAction?: { label: string; href: string }
  status?: React.ReactNode
}) {
  return (
    <section
      data-slot="hero-centered"
      className={cn(
        "relative flex w-full flex-col items-center px-6 pt-28 pb-24 text-center sm:px-8 sm:pt-36 sm:pb-32",
        className
      )}
      {...props}
    >
      <div className="mx-auto flex w-full max-w-[75rem] flex-col items-center">
        {eyebrow ? (
          <Reveal>
            <p className="text-muted-foreground mb-7 font-mono text-[0.6875rem] tracking-[0.24em] uppercase">
              {eyebrow}
            </p>
          </Reveal>
        ) : null}

        <Reveal delay={0.05}>
          <h1 className="mx-auto max-w-[14ch] font-[family-name:var(--font-display)] text-[clamp(2.75rem,7vw,5rem)] leading-[1.04] text-balance">
            {title}
          </h1>
        </Reveal>

        {description ? (
          <Reveal delay={0.1}>
            <p className="text-muted-foreground mx-auto mt-7 max-w-[52ch] text-[1.0625rem] leading-[1.6] text-pretty">
              {description}
            </p>
          </Reveal>
        ) : null}

        {primaryAction || secondaryAction ? (
          <Reveal delay={0.15}>
            <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
              {primaryAction ? (
                <Button asChild size="lg">
                  <a href={primaryAction.href}>
                    {primaryAction.label}
                    <ArrowRightIcon />
                  </a>
                </Button>
              ) : null}
              {secondaryAction ? (
                <Button asChild size="lg" variant="outline">
                  <a href={secondaryAction.href}>{secondaryAction.label}</a>
                </Button>
              ) : null}
            </div>
          </Reveal>
        ) : null}

        {status ? (
          <Reveal delay={0.2}>
            <div className="text-muted-foreground mt-8 flex items-center justify-center gap-2 text-[0.8125rem]">
              <span className="brand-dot inline-block size-1.5 rounded-full" />
              {status}
            </div>
          </Reveal>
        ) : null}
      </div>
    </section>
  )
}

export { HeroCentered }
