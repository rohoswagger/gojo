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

export { Section }
