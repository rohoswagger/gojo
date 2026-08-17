import * as React from "react"

import { cn } from "@/lib/utils"
import {
  Section,
  SectionDescription,
  SectionEyebrow,
  SectionHeader,
  SectionTitle,
  SectionContent,
} from "@/components/section"
import { RevealGroup, RevealItem } from "@/components/reveal"

type Feature = {
  icon?: React.ReactNode
  title: React.ReactNode
  description: React.ReactNode
}

function FeatureGrid({
  eyebrow,
  title,
  description,
  features,
  columns = 3,
  className,
  ...props
}: Omit<React.ComponentProps<"section">, "title"> & {
  eyebrow?: React.ReactNode
  title?: React.ReactNode
  description?: React.ReactNode
  features: Feature[]
  columns?: 2 | 3 | 4
}) {
  return (
    <Section data-slot="feature-grid" className={cn(className)} {...props}>
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
            "grid gap-4",
            columns === 2 && "sm:grid-cols-2",
            columns === 3 && "sm:grid-cols-2 lg:grid-cols-3",
            columns === 4 && "sm:grid-cols-2 lg:grid-cols-4"
          )}
        >
          {features.map((f, i) => (
            <RevealItem
              key={i}
              className="bg-card rounded-xl border p-7 shadow-[var(--shadow-raised),var(--inset-highlight)]"
            >
              {f.icon ? (
                <div className="bg-accent text-foreground mb-5 flex size-9 items-center justify-center rounded-md [&_svg]:size-4">
                  {f.icon}
                </div>
              ) : null}
              <h3 className="mb-2 font-[family-name:var(--font-display)] text-[1.1875rem] leading-snug">
                {f.title}
              </h3>
              <p className="text-muted-foreground text-[0.9375rem] leading-[1.6] text-pretty">
                {f.description}
              </p>
            </RevealItem>
          ))}
        </RevealGroup>
      </SectionContent>
    </Section>
  )
}

export { FeatureGrid }
