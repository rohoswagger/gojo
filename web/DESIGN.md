---
version: alpha
name: Gojo
description: Warm macOS editorial surfaces around a focused dark hero.
colors:
  primary: "#4A46CF"
  primary-soft: "#F0F0FB"
  ink: "#171717"
  ink-muted: "#737373"
  surface: "#FFFFFF"
  surface-muted: "#FAFAFA"
  warm-ink: "#2B1B12"
  warm-muted: "#6B5245"
  warm-accent: "#B9472D"
  warm-surface: "#FDF6EE"
  hero: "#0A0B12"
typography:
  display:
    fontFamily: "ui-rounded, SF Pro Rounded, system-ui, sans-serif"
    fontSize: 3.5rem
    fontWeight: 550
    lineHeight: 1.06
    letterSpacing: "-0.035em"
  heading:
    fontFamily: "ui-rounded, SF Pro Rounded, system-ui, sans-serif"
    fontSize: 2.5rem
    fontWeight: 550
    lineHeight: 1.1
    letterSpacing: "-0.03em"
  body:
    fontFamily: "ui-sans-serif, system-ui, SF Pro Text, sans-serif"
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "ui-monospace, SF Mono, JetBrains Mono, monospace"
    fontSize: 0.6875rem
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.14em"
rounded:
  control: 8px
  card: 16px
  panel: 22px
  pill: 999px
spacing:
  xs: 8px
  sm: 16px
  md: 24px
  lg: 32px
  xl: 64px
components:
  link:
    textColor: "{colors.primary}"
    typography: "{typography.body}"
  link-editorial:
    textColor: "{colors.warm-accent}"
    typography: "{typography.body}"
  supporting-copy:
    textColor: "{colors.ink-muted}"
    typography: "{typography.body}"
  surface-muted:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.ink}"
  selected-chip:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
    rounded: "{rounded.pill}"
    padding: 8px
  editorial-supporting:
    backgroundColor: "{colors.warm-surface}"
    textColor: "{colors.warm-muted}"
    rounded: "{rounded.card}"
    padding: 24px
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: 12px
  button-primary-hover:
    backgroundColor: "{colors.hero}"
    textColor: "{colors.surface}"
  card-editorial:
    backgroundColor: "{colors.warm-surface}"
    textColor: "{colors.warm-ink}"
    rounded: "{rounded.card}"
    padding: 24px
  hero-panel:
    backgroundColor: "{colors.hero}"
    textColor: "{colors.surface}"
    rounded: "{rounded.panel}"
    padding: 32px
---

## Overview

Gojo uses one system across the homepage, feature pages, comparisons, downloads, legal pages, and press materials. The visual language pairs a focused sunset hero with quiet editorial reading surfaces. Product UI is evidence, not decoration.

The landing and high-emphasis marketing headings deliberately use a separate rounded display font. That is not the body font: reading copy, navigation, controls, and quieter utility pages stay on the native sans-serif stack. `app/design-tokens.css` is the runtime source of truth. This file describes how agents and contributors apply those roles. Do not introduce a page-local font stack, content width, or brand palette.

## Colors

- **Primary:** Indigo is used for standard links, focus rings, and neutral product accents.
- **Warm accent:** Clay marks editorial labels and calls to action on warm marketing surfaces.
- **Hero:** Near-black supports the sunset photograph and real product captures.
- **Surfaces:** White is the default reading ground. Warm cream belongs to feature, comparison, and press storytelling.
- Use `--ink-3` or darker for text. Lighter ink tokens are borders and decoration only.

## Typography

- Landing and high-emphasis marketing display text uses `var(--font-marketing-display)`: the macOS rounded system stack.
- Body copy, controls, and generic UI headings use `var(--font-interface)`: the native sans-serif system stack.
- Kicker labels, metadata, and technical values use `var(--font-technical)`.
- `--display`, `--body`, and `--mono` are compatibility aliases for the existing site skin. They must not define separate stacks.
- No webfonts. On macOS the display role resolves to SF Pro Rounded; non-Apple screenshot environments fall back to their local system face, so glyph shapes and widths may differ even when the CSS is identical.
- Use the shared `--step-display`, `--step-h2`, `--step-h3`, and `--step-lede` scales before adding a page-specific size.

## Layout

- `--page` is the maximum shared canvas. `.wrap` and `.shell` apply it with `--gutter`.
- `--measure` is the maximum reading width for prose.
- `--section-y` controls vertical section rhythm.
- Dark photographic heroes use an inset `--mat` and `--radius-panel`, then transition into a light reading surface.
- Marketing heroes may use a two-column layout above 900px. Collapse to one column below it.
- Mobile content keeps at least `--gutter` from the viewport edge. Dense card grids collapse by 900px and become one column by 640px.

## Shapes

- Controls use `--radius-control`.
- Content cards use `--radius-card`.
- Inset hero and feature panels use `--radius-panel`.
- Pills are reserved for compact actions, tabs, and status chips.
- Shadows belong to floating product evidence and dark hero media. Reading cards use borders first.

## Components

- `GojoHeader` and `GojoFooter` are the persistent site chrome. Use `GojoHeader overlay` only on a dark photographic hero.
- `.btn.btn-primary` is the default high-emphasis action. Keep one dominant action per section.
- `.wrap` and `.shell` are the standard page-width primitives.
- `.article-shell[data-gojo-editorial="warm"]` opts editorial pages into the warm storytelling system.
- Product screenshots and videos must show the shipping UI and include descriptive text or captions.
- New page-specific styles may compose tokens but must not redefine typography stacks or the shared layout scale.

## Do's and Don'ts

- **Do** reuse runtime tokens and shared chrome before writing page-specific CSS.
- **Do** test desktop and mobile layouts and attach both screenshots when responsive behavior changes.
- **Do** keep body copy on quiet, high-contrast surfaces.
- **Don't** build a page entirely from ad hoc Tailwind typography and spacing utilities.
- **Don't** add raw `font-family` declarations outside `app/design-tokens.css`.
- **Don't** invent a new accent palette or page width for one route.
- **Don't** wrap real Gojo UI in fake device chrome that competes with the product.
