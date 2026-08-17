import * as React from "react"

import { cn } from "@/lib/utils"

const widths = {
  narrow: "max-w-[46rem]",
  default: "max-w-[75rem]",
  wide: "max-w-[90rem]",
  full: "max-w-none",
}

function Section({
  className,
  width = "default",
  children,
  ...props
}: React.ComponentProps<"section"> & { width?: keyof typeof widths }) {
  return (
    <section
      data-slot="section"
      className={cn("w-full px-6 py-24 sm:px-8 sm:py-32", className)}
      {...props}
    >
      <div className={cn("mx-auto w-full", widths[width])}>{children}</div>
    </section>
  )
}

function SectionHeader({
  className,
  align = "center",
  ...props
}: React.ComponentProps<"div"> & { align?: "start" | "center" }) {
  return (
    <div
      data-slot="section-header"
      className={cn(
        "flex flex-col gap-5",
        align === "center" ? "items-center text-center" : "items-start text-left",
        className
      )}
      {...props}
    />
  )
}

/** Mono, uppercase, widely tracked — the counterweight to tight display type. */
function SectionEyebrow({ className, ...props }: React.ComponentProps<"p">) {
  return (
    <p
      data-slot="section-eyebrow"
      className={cn(
        "text-muted-foreground font-mono text-[0.6875rem] tracking-[0.24em] uppercase",
        className
      )}
      {...props}
    />
  )
}

function SectionTitle({ className, ...props }: React.ComponentProps<"h2">) {
  return (
    <h2
      data-slot="section-title"
      className={cn(
        "font-[family-name:var(--font-display)] text-[clamp(2rem,4.5vw,3.25rem)] leading-[1.08] text-balance",
        className
      )}
      {...props}
    />
  )
}

function SectionDescription({ className, ...props }: React.ComponentProps<"p">) {
  return (
    <p
      data-slot="section-description"
      className={cn(
        "text-muted-foreground max-w-[52ch] text-[1.0625rem] leading-[1.6] text-pretty",
        className
      )}
      {...props}
    />
  )
}

function SectionContent({ className, ...props }: React.ComponentProps<"div">) {
  return <div data-slot="section-content" className={cn("mt-16", className)} {...props} />
}

export {
  Section,
  SectionHeader,
  SectionEyebrow,
  SectionTitle,
  SectionDescription,
  SectionContent,
}
