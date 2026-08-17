import * as React from "react"

import { cn } from "@/lib/utils"
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion"
import {
  Section,
  SectionDescription,
  SectionEyebrow,
  SectionHeader,
  SectionTitle,
  SectionContent,
} from "@/components/section"
import { Reveal } from "@/components/reveal"

type Faq = { question: React.ReactNode; answer: React.ReactNode }

function FaqAccordion({
  eyebrow,
  title,
  description,
  items,
  className,
  ...props
}: Omit<React.ComponentProps<"section">, "title"> & {
  eyebrow?: React.ReactNode
  title?: React.ReactNode
  description?: React.ReactNode
  items: Faq[]
}) {
  return (
    <Section data-slot="faq-accordion" width="narrow" className={cn(className)} {...props}>
      {title ? (
        <SectionHeader>
          {eyebrow ? <SectionEyebrow>{eyebrow}</SectionEyebrow> : null}
          <SectionTitle className="max-w-[20ch]">{title}</SectionTitle>
          {description ? <SectionDescription>{description}</SectionDescription> : null}
        </SectionHeader>
      ) : null}

      <SectionContent>
        <Reveal>
          <Accordion type="single" collapsible className="w-full">
            {items.map((f, i) => (
              <AccordionItem key={i} value={`item-${i}`}>
                <AccordionTrigger className="text-left text-[1rem]">
                  {f.question}
                </AccordionTrigger>
                <AccordionContent className="text-[0.9375rem] leading-[1.65]">
                  {f.answer}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </Reveal>
      </SectionContent>
    </Section>
  )
}

export { FaqAccordion }
