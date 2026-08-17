import * as React from "react"
import { CheckIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Section,
  SectionDescription,
  SectionEyebrow,
  SectionHeader,
  SectionTitle,
  SectionContent,
} from "@/components/section"
import { RevealGroup, RevealItem } from "@/components/reveal"

type Tier = {
  name: string
  price: React.ReactNode
  cadence?: React.ReactNode
  description?: React.ReactNode
  features: string[]
  action: { label: string; href: string }
  featured?: boolean
}

/**
 * The featured tier is distinguished by elevation and a badge, not by colour —
 * the brand hue stays off pricing surfaces like everywhere else.
 */
function PricingTiers({
  eyebrow,
  title,
  description,
  tiers,
  className,
  ...props
}: Omit<React.ComponentProps<"section">, "title"> & {
  eyebrow?: React.ReactNode
  title?: React.ReactNode
  description?: React.ReactNode
  tiers: Tier[]
}) {
  return (
    <Section data-slot="pricing-tiers" className={cn(className)} {...props}>
      {title ? (
        <SectionHeader>
          {eyebrow ? <SectionEyebrow>{eyebrow}</SectionEyebrow> : null}
          <SectionTitle className="max-w-[18ch]">{title}</SectionTitle>
          {description ? <SectionDescription>{description}</SectionDescription> : null}
        </SectionHeader>
      ) : null}

      <SectionContent>
        <RevealGroup
          className={cn(
            "grid items-start gap-4",
            tiers.length === 2 && "sm:grid-cols-2",
            tiers.length >= 3 && "sm:grid-cols-2 lg:grid-cols-3"
          )}
        >
          {tiers.map((t) => (
            <RevealItem
              key={t.name}
              className={cn(
                "bg-card relative flex flex-col rounded-2xl border p-8",
                t.featured
                  ? "brand-glow shadow-[var(--shadow-overlay),var(--inset-highlight)]"
                  : "shadow-[var(--shadow-raised),var(--inset-highlight)]"
              )}
            >
              <div className="mb-5 flex items-center justify-between gap-3">
                <p className="font-mono text-[0.6875rem] tracking-[0.2em] uppercase">
                  {t.name}
                </p>
                {t.featured ? <Badge variant="secondary">Popular</Badge> : null}
              </div>

              <p className="flex items-baseline gap-1.5">
                <span className="font-[family-name:var(--font-display)] text-[2.75rem] leading-none">
                  {t.price}
                </span>
                {t.cadence ? (
                  <span className="text-muted-foreground text-[0.875rem]">{t.cadence}</span>
                ) : null}
              </p>

              {t.description ? (
                <p className="text-muted-foreground mt-3 text-[0.9375rem] leading-[1.6]">
                  {t.description}
                </p>
              ) : null}

              <ul className="mt-7 flex flex-col gap-3">
                {t.features.map((f) => (
                  <li key={f} className="flex items-start gap-2.5 text-[0.9375rem]">
                    <CheckIcon className="text-muted-foreground mt-[0.2rem] size-4 shrink-0" />
                    <span className="text-pretty">{f}</span>
                  </li>
                ))}
              </ul>

              <Button
                asChild
                size="lg"
                variant={t.featured ? "default" : "outline"}
                className="mt-8 w-full"
              >
                <a href={t.action.href}>{t.action.label}</a>
              </Button>
            </RevealItem>
          ))}
        </RevealGroup>
      </SectionContent>
    </Section>
  )
}

export { PricingTiers }
