import * as React from "react";

import { cn } from "@/lib/utils";
import {
  Section,
  SectionDescription,
  SectionEyebrow,
  SectionHeader,
  SectionTitle,
  SectionContent,
} from "@/components/section";
import { RevealGroup, RevealItem } from "@/components/reveal";

/**
 * Large-media feature cards: a brand-washed canvas holding a floating
 * vignette, captioned below. Use it when each feature has something worth
 * *showing*, not just naming.
 *
 * Composable rather than data-driven because the media slot is the point:
 *
 *   <FeatureShowcase title="…" actions={<Button>…</Button>}>
 *     <FeatureShowcaseCard>
 *       <FeatureShowcaseMedia>
 *         <FeatureShowcaseFloat>…any vignette…</FeatureShowcaseFloat>
 *       </FeatureShowcaseMedia>
 *       <FeatureShowcaseCaption icon={<BoxIcon />} title="…">…</FeatureShowcaseCaption>
 *     </FeatureShowcaseCard>
 *   </FeatureShowcase>
 */

function FeatureShowcase({
  eyebrow,
  title,
  description,
  actions,
  columns = 3,
  className,
  children,
  ...props
}: Omit<React.ComponentProps<"section">, "title"> & {
  eyebrow?: React.ReactNode;
  title?: React.ReactNode;
  description?: React.ReactNode;
  /** Rendered opposite the header on wide viewports — CTA buttons, usually. */
  actions?: React.ReactNode;
  columns?: 2 | 3;
}) {
  return (
    <Section data-slot="feature-showcase" className={cn(className)} {...props}>
      {title ? (
        <div className="flex flex-col gap-8 lg:flex-row lg:items-end lg:justify-between">
          <SectionHeader align="start">
            {eyebrow ? <SectionEyebrow>{eyebrow}</SectionEyebrow> : null}
            <SectionTitle className="max-w-[16ch]">{title}</SectionTitle>
            {description ? (
              <SectionDescription>{description}</SectionDescription>
            ) : null}
          </SectionHeader>
          {actions ? (
            <div className="flex shrink-0 flex-wrap items-center gap-3">
              {actions}
            </div>
          ) : null}
        </div>
      ) : null}

      <SectionContent>
        <RevealGroup
          initial={false}
          className={cn(
            "grid gap-x-8 gap-y-14",
            columns === 2 && "sm:grid-cols-2",
            columns === 3 && "sm:grid-cols-2 lg:grid-cols-3",
          )}
        >
          {children}
        </RevealGroup>
      </SectionContent>
    </Section>
  );
}

function FeatureShowcaseCard({
  className,
  ...props
}: React.ComponentProps<typeof RevealItem>) {
  return (
    <RevealItem
      data-slot="feature-showcase-card"
      className={cn("group flex flex-col gap-6", className)}
      {...props}
    />
  );
}

/**
 * The canvas. A brand wash mixed from the tokens — light from above, settling
 * toward the base — so it re-themes with the project instead of shipping a
 * hardcoded pastel. Streaks are the light catching; they stay behind whatever
 * floats on top.
 */
function FeatureShowcaseMedia({
  className,
  children,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="feature-showcase-media"
      className={cn(
        "bg-background relative flex aspect-square items-center justify-center overflow-hidden rounded-2xl p-7 shadow-(--shadow-hairline) sm:p-9",
        // Brand at alpha over the base, never mixed with it: --background
        // carries an explicit hue of 0, so an oklch mix toward it rotates
        // through magenta. Transparent's components are `none`, which keeps
        // the brand hue and only scales alpha.
        "bg-[linear-gradient(178deg,color-mix(in_oklch,var(--brand)_20%,transparent)_0%,color-mix(in_oklch,var(--brand)_11%,transparent)_52%,color-mix(in_oklch,var(--brand)_5%,transparent)_100%)]",
        className,
      )}
      {...props}
    >
      <div aria-hidden className="absolute inset-0">
        <div className="absolute top-[12%] left-0 h-[6.5%] w-[42%] rounded-r-md bg-white/25 dark:bg-white/[0.05]" />
        <div className="absolute top-[21%] left-0 h-[6.5%] w-[26%] rounded-r-md bg-white/15 dark:bg-white/[0.03]" />
        <div className="absolute top-[58%] right-0 h-[6.5%] w-[30%] rounded-l-md bg-white/10 dark:bg-white/[0.03]" />
      </div>
      {children}
    </div>
  );
}

/**
 * A vignette hovering above the wash: card surface, overlay shadow, and a
 * translucent mat behind it that reads as the glass it sits on. Lifts a
 * touch when the card is hovered — the one authored moment here.
 */
function FeatureShowcaseFloat({
  overlay,
  className,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  /**
   * Positioned children that ride the hover lift but sit outside the clipped
   * panel — cursors, chips, badges overlapping the panel's edge. Anchored to
   * the panel, so they move with it.
   */
  overlay?: React.ReactNode;
}) {
  return (
    <div
      data-slot="feature-showcase-float"
      className={cn(
        "relative w-full max-w-[21rem]",
        "transition-transform duration-(--duration-slow) ease-(--ease-swagui) group-hover:-translate-y-1.5 motion-reduce:transform-none",
        className,
      )}
      {...props}
    >
      <div
        aria-hidden
        className="absolute -inset-2.5 rounded-[calc(var(--radius-xl)+0.625rem)] bg-white/10 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.35)] dark:bg-white/[0.03] dark:shadow-[inset_0_0_0_1px_rgb(255_255_255/0.08)]"
      />
      <div className="bg-card relative overflow-hidden rounded-xl shadow-(--shadow-overlay)">
        {children}
      </div>
      {overlay}
    </div>
  );
}

function FeatureShowcaseCaption({
  icon,
  title,
  className,
  children,
  ...props
}: Omit<React.ComponentProps<"div">, "title"> & {
  icon?: React.ReactNode;
  title: React.ReactNode;
}) {
  return (
    <div
      data-slot="feature-showcase-caption"
      className={cn("flex flex-col gap-2", className)}
      {...props}
    >
      <h3 className="flex items-center gap-2.5 font-[family-name:var(--font-display)] text-[1.125rem] leading-snug">
        {icon ? (
          <span
            aria-hidden
            className="text-foreground/70 flex [&_svg]:size-[1.125rem]"
          >
            {icon}
          </span>
        ) : null}
        {title}
      </h3>
      <p className="text-muted-foreground text-[0.9375rem] leading-[1.6] text-pretty">
        {children}
      </p>
    </div>
  );
}

export {
  FeatureShowcase,
  FeatureShowcaseCard,
  FeatureShowcaseMedia,
  FeatureShowcaseFloat,
  FeatureShowcaseCaption,
};
