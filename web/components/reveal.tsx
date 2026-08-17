"use client"

import * as React from "react"
import { motion, useReducedMotion, type Variants } from "motion/react"

import { cn } from "@/lib/utils"

/**
 * Scroll-reveal wrapper. Enters once, on the house curve, slower than a UI
 * transition — the pacing is most of the effect.
 *
 * `motion` is a block-level dependency by design; swagui primitives stay on
 * pure CSS so app bundles never pay for it.
 */

const DISTANCE = 20

function useVariants(delay: number): Variants {
  const reduced = useReducedMotion()
  return React.useMemo(
    () => ({
      hidden: reduced ? { opacity: 0 } : { opacity: 0, y: DISTANCE },
      visible: {
        opacity: 1,
        y: 0,
        transition: {
          duration: reduced ? 0.2 : 0.65,
          ease: [0.22, 1, 0.36, 1],
          delay,
        },
      },
    }),
    [reduced, delay]
  )
}

function Reveal({
  className,
  delay = 0,
  amount = 0.3,
  ...props
}: React.ComponentProps<typeof motion.div> & { delay?: number; amount?: number }) {
  const variants = useVariants(delay)
  return (
    <motion.div
      data-slot="reveal"
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, amount }}
      variants={variants}
      className={cn(className)}
      {...props}
    />
  )
}

/** Wrap RevealItem children to stagger them in sequence. */
function RevealGroup({
  className,
  stagger = 0.08,
  amount = 0.2,
  ...props
}: React.ComponentProps<typeof motion.div> & { stagger?: number; amount?: number }) {
  return (
    <motion.div
      data-slot="reveal-group"
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, amount }}
      variants={{
        hidden: {},
        visible: { transition: { staggerChildren: stagger } },
      }}
      className={cn(className)}
      {...props}
    />
  )
}

function RevealItem({ className, ...props }: React.ComponentProps<typeof motion.div>) {
  const variants = useVariants(0)
  return (
    <motion.div
      data-slot="reveal-item"
      variants={variants}
      className={cn(className)}
      {...props}
    />
  )
}

export { Reveal, RevealGroup, RevealItem }
