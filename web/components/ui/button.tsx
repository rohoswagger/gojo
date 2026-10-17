import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  [
    "inline-flex max-w-full items-center justify-center gap-2 rounded-full text-center text-base font-medium whitespace-normal [overflow-wrap:anywhere]",
    "disabled:pointer-events-none disabled:opacity-40",
    "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
    "transition-[filter,background-color,border-color,color,box-shadow] duration-(--duration-press) ease-(--ease-swagui)",
    "focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-ring",
    "aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40",
  ],
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground shadow-(--shadow-raised) hover:brightness-125",
        destructive:
          "bg-destructive text-white shadow-(--shadow-raised) hover:brightness-110 focus-visible:outline-destructive dark:bg-destructive/70",
        outline:
          "border border-border/80 bg-background shadow-(--shadow-hairline) hover:bg-accent hover:text-accent-foreground dark:border-input dark:bg-input/30",
        secondary:
          "bg-secondary text-secondary-foreground shadow-(--shadow-hairline) hover:brightness-[0.97] dark:hover:brightness-125",
        ghost:
          "hover:bg-accent hover:text-accent-foreground dark:hover:bg-accent/50",
        link: "text-primary underline-offset-4 decoration-from-font hover:underline",
      },
      size: {
        default: "min-h-11 px-4 py-2 has-[>svg]:px-3.5",
        xs: "min-h-11 gap-1 px-2.5 py-2 text-xs has-[>svg]:px-2 [&_svg:not([class*='size-'])]:size-3",
        sm: "min-h-11 gap-1.5 px-3.5 py-2 text-[0.8125rem] has-[>svg]:px-3",
        lg: "min-h-11 px-6 py-2.5 text-base has-[>svg]:px-5",
        icon: "size-11",
        "icon-xs": "size-11 [&_svg:not([class*='size-'])]:size-3",
        "icon-sm": "size-11",
        "icon-lg": "size-11",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean
  }) {
  const Comp = asChild ? Slot.Root : "button"

  return (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants }
