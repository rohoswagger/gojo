import * as React from "react"
import { ArrowRightIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Reveal } from "@/components/reveal"

/**
 * Closing call to action. The brand colour appears here only as the ambient
 * glow behind the panel — never on the button itself.
 */
function CtaBand({
  title,
  description,
  primaryAction,
  secondaryAction,
  className,
  ...props
}: Omit<React.ComponentProps<"section">, "title"> & {
  title: React.ReactNode
  description?: React.ReactNode
  primaryAction?: { label: string; href: string }
  secondaryAction?: { label: string; href: string }
}) {
  return (
    <section
      data-slot="cta-band"
      className={cn("w-full px-6 py-24 sm:px-8 sm:py-32", className)}
      {...props}
    >
      <Reveal className="mx-auto w-full max-w-[62rem]">
        <div className="brand-glow bg-card relative overflow-hidden rounded-2xl border px-8 py-16 text-center shadow-[var(--shadow-raised),var(--inset-highlight)] sm:px-16">
          <h2 className="mx-auto max-w-[18ch] font-[family-name:var(--font-display)] text-[clamp(1.875rem,3.5vw,2.75rem)] leading-[1.1] text-balance">
            {title}
          </h2>

          {description ? (
            <p className="text-muted-foreground mx-auto mt-5 max-w-[46ch] text-[1.0625rem] leading-[1.6] text-pretty">
              {description}
            </p>
          ) : null}

          {primaryAction || secondaryAction ? (
            <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
              {primaryAction ? (
                <Button asChild size="lg">
                  <a href={primaryAction.href}>
                    {primaryAction.label}
                    <ArrowRightIcon />
                  </a>
                </Button>
              ) : null}
              {secondaryAction ? (
                <Button asChild size="lg" variant="ghost">
                  <a href={secondaryAction.href}>{secondaryAction.label}</a>
                </Button>
              ) : null}
            </div>
          ) : null}
        </div>
      </Reveal>
    </section>
  )
}

export { CtaBand }
