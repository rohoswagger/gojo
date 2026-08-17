import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  [
    "inline-flex shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium whitespace-nowrap outline-none",
    "disabled:pointer-events-none disabled:opacity-40",
    "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
    // swagui: hover is a brightness filter rather than a colour swap, so
    // gradients and inset rings survive it. Press is a universal 120ms scale.
    "transition-[transform,filter,background-color,border-color,box-shadow] duration-(--duration-press) ease-(--ease-swagui)",
    "active:scale-[0.97]",
    // The focus ring is the one control surface where the brand colour lands.
    "focus-visible:ring-2 focus-visible:ring-ring/60 focus-visible:ring-offset-2 focus-visible:ring-offset-background",
    "aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40",
  ],
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground shadow-(--shadow-raised) hover:brightness-125",
        destructive:
          "bg-destructive text-white shadow-(--shadow-raised) hover:brightness-110 focus-visible:ring-destructive/40 dark:bg-destructive/70",
        outline:
          "border border-border/80 bg-background shadow-(--shadow-hairline) hover:bg-accent hover:text-accent-foreground dark:border-input dark:bg-input/30",
        secondary:
          "bg-secondary text-secondary-foreground shadow-(--shadow-hairline) hover:brightness-[0.97] dark:hover:brightness-125",
        ghost:
          "hover:bg-accent hover:text-accent-foreground dark:hover:bg-accent/50",
        link: "text-primary underline-offset-4 decoration-from-font hover:underline active:scale-100",
      },
      size: {
        default: "h-9 px-4 py-2 has-[>svg]:px-3.5",
        xs: "h-6 gap-1 px-2.5 text-xs has-[>svg]:px-2 [&_svg:not([class*='size-'])]:size-3",
        sm: "h-8 gap-1.5 px-3.5 text-[0.8125rem] has-[>svg]:px-3",
        lg: "h-11 px-6 text-[0.9375rem] has-[>svg]:px-5",
        icon: "size-9",
        "icon-xs": "size-6 [&_svg:not([class*='size-'])]:size-3",
        "icon-sm": "size-8",
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
