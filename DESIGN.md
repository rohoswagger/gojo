---
name: Gojo
description: MacBook productivity hub with a warm editorial marketing system rooted in the real notch interface.
colors:
  ember-red: "#bd4328"
  coral-orange: "#ee6a38"
  sunset-peach: "#ffb08a"
  warm-cream: "#fff5ec"
  cream-panel: "#fff1df"
  cream-card: "#fffaf6"
  cream-tint: "#fff0e7"
  white: "#ffffff"
  near-black: "#0a0b12"
  editorial-dark: "#160c09"
  editorial-panel: "#21110d"
  ink-strong: "rgba(0, 0, 0, 0.9)"
  ink-body: "rgba(0, 0, 0, 0.75)"
  ink-muted: "rgba(0, 0, 0, 0.55)"
  rule: "#e6e6e6"
  rule-soft: "#f0f0f0"
  success: "#1a7f4b"
  danger: "#b3372c"
typography:
  display:
    fontFamily: "ui-rounded, SF Pro Rounded, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(2.5rem, 5.2vw, 3.5rem)"
    fontWeight: 550
    lineHeight: 1.06
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "ui-rounded, SF Pro Rounded, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(1.75rem, 3vw, 2.5rem)"
    fontWeight: 550
    lineHeight: 1.1
    letterSpacing: "-0.03em"
  title:
    fontFamily: "ui-rounded, SF Pro Rounded, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(1.25rem, 1.8vw, 1.5rem)"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  body:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, SF Pro Text, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "ui-monospace, SF Mono, JetBrains Mono, monospace"
    fontSize: "0.6875rem"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "0.14em"
rounded:
  sm: "6px"
  md: "8px"
  lg: "12px"
  xl: "14px"
  xxl: "16px"
  section: "18px"
  hero-shell: "22px"
  pill: "999px"
spacing:
  gutter: "clamp(1.25rem, 4vw, 2rem)"
  section-y: "clamp(3.5rem, 7vw, 6rem)"
  page: "76rem"
  measure: "44rem"
components:
  button-primary:
    backgroundColor: "{colors.ink-strong}"
    textColor: "{colors.white}"
    rounded: "{rounded.md}"
    padding: "0.6875rem 1.25rem"
  button-ghost:
    backgroundColor: "{colors.white}"
    textColor: "{colors.ink-strong}"
    rounded: "{rounded.md}"
    padding: "0.6875rem 1.25rem"
  editorial-hero-button:
    backgroundColor: "{colors.white}"
    textColor: "{colors.near-black}"
    rounded: "{rounded.md}"
    padding: "0.8125rem 1.5rem"
  feature-card:
    backgroundColor: "{colors.cream-card}"
    textColor: "{colors.ink-strong}"
    rounded: "{rounded.xxl}"
    padding: "1.35rem 1.5rem 1.5rem"
  editorial-dark-panel:
    backgroundColor: "{colors.editorial-panel}"
    textColor: "{colors.white}"
    rounded: "{rounded.section}"
    padding: "clamp(2.5rem, 5vw, 4rem)"
---

# Design System: Gojo

## Overview

**Creative North Star: "The Sunset Notch Desk"**

Gojo's marketing world makes the MacBook notch feel like a warm, useful desk surface at the top edge of the screen. The homepage is the visual authority: sunset photography, a dark scrim, a real notch demo, and restrained native controls define the brand. Every marketing page should persuade by making the product visible quickly, then proving breadth with real interface evidence.

The base site skin still supplies the structural system: 76rem page width, 44rem reading measure, 8px cards and buttons, sticky navigation, hairline rules, tight rounded display type, and no decorative clutter. Features and Alternatives use the warm editorial variant on top of that base: sunset-photo heroes, a flagship dark dictation spotlight, job-based feature chapters, three comparison decision lanes, product screenshots, and recognizable competitor marks.

**Key Characteristics:**
- Real product evidence appears in the first viewport: notch interface screenshots on Features, comparison marks on Alternatives, and the notch demo on the homepage.
- Warm brand accents are ember red, coral orange, peach, cream, white, and near-black.
- Editorial pages vary pace with dark heroes, a dark dictation spotlight, cream chapter grids, compact signal checks, three-lane comparison libraries, dark proof bands, and centered comparison devices.
- The tone is persuasive, tactile, and Mac-native, not generic SaaS.

## Colors

The palette is warm and photographic: dark sunset panels carry white type, while cream surfaces make screenshots and comparison marks feel editorial rather than clinical.

### Primary
- **Ember Red**: Primary Gojo brand accent for editorial links, Gojo marks, orbit centers, selected comparison surfaces, and warm hover states.
- **Coral Orange**: Secondary warm accent for glows, focus rings in warm editorial pages, signal bars, and gradient highlights.

### Secondary
- **Sunset Peach**: Soft highlight for links and small labels on dark editorial panels.
- **Warm Cream**: Page warmth for editorial sections and pale background fields.
- **Cream Panel**: Tinted editorial callouts such as "why" panels and fair-choice panels.
- **Cream Card**: Feature and Alternative cards in warm editorial grids.
- **Cream Tint**: Gojo-tinted comparison cells and answer boxes.

### Neutral
- **White**: Button fill on dark heroes, primary text over dark panels, and core page surface.
- **Near Black**: The homepage panel and dark UI wells.
- **Editorial Dark**: Warm dark hero base for Features and Alternatives.
- **Editorial Panel**: Warm dark chapter panels and CTA panels.
- **Ink Strong / Body / Muted**: Alpha-black text tiers for light surfaces.
- **Rule / Rule Soft**: Hairline borders and internal dividers.
- **Success / Danger**: Yes and No comparison states. Pair color with text and icons.

### Named Rules

**The No Blue Brand Rule.** Gojo brand accents are never blue or purple. If an inherited base token is blue, override it in the warm editorial world before using it as Gojo identity.

**The Evidence First Rule.** A first viewport must show the real notch interface, real screenshots, or recognizable comparison marks before abstract claims.

## Typography

**Display Font:** `ui-rounded, "SF Pro Rounded", system-ui, -apple-system, sans-serif`
**Body Font:** `ui-sans-serif, system-ui, -apple-system, "SF Pro Text", sans-serif`
**Label/Mono Font:** `ui-monospace, "SF Mono", "JetBrains Mono", monospace`

**Character:** Rounded display type gives the product a tactile Mac-native voice. Body text stays system-native and direct; mono labels act as quiet metadata rather than decoration.

### Hierarchy
- **Display** (550, responsive clamp, tight line-height): Hero headlines, large editorial section titles, and centered comparison titles.
- **Headline** (550, responsive clamp, tight line-height): Section headings such as library heads, pricing, and major proof bands.
- **Title** (600, compact responsive size): Cards, FAQ questions, plan names, and comparison product names.
- **Body** (400, 1rem, 1.5-1.75 line-height): Product explanations, article body, facts, and comparison copy. Keep reading text near the 44rem measure.
- **Label** (mono, 0.6875rem, uppercase, tracked): Breadcrumb metadata, section labels, table corners, and small trust facts.

### Named Rules

**The Rounded Native Rule.** Display type should feel like it belongs in macOS utility UI: rounded, tight, and useful, not magazine-serif or corporate grotesque.

## Layout

The core layout uses a 76rem page width, a 44rem reading measure, and a responsive gutter. Home sections alternate between two-column product proof, full-width feature acts, and a centered pricing pair. Article pages keep a narrow reading column unless a feature or comparison needs evidence.

Features and Alternatives deliberately break article monotony. The Features hub opens with a two-column headline/context row followed by one dominant, full-width notch capture in a subtle MacBook bezel. Use `/screenshots/windows.png` at its native 1322x418 dimensions as the shipping authority for this hero; do not replace it with layered tilted crops, sticky-note decoration, or low-resolution reconstructions. The rest of the hub is chaptered by job: movement workflows, Mac-awareness workflows, and compact small checks. Feature detail pages keep the warm hero and put a populated screenshot well beside the headline.

The Alternatives hub uses a Gojo-centered orbit of competitor marks in the first viewport, then groups every guide into three decision lanes: Notch & Island Utilities, Focused Specialists, and Power Layers. Power Layers uses the sunset photograph as a material field instead of another flat card column. Alternative detail pages center the hero and place the `Versus` comparison device in the first viewport.

Responsive behavior is explicit: major split grids collapse to one column below tablet widths; feature chapter grids move from three columns to two, then one; compact feature cards preserve a wide copy column with a 5.5rem signal column on mobile; Alternatives lanes move from three columns to two, then one; comparison tables become two-column mobile rows; navigation wraps instead of crushing controls. The page must not overflow at 390px.

## Elevation & Depth

Depth is a hybrid of tonal layering and selective shadows. Light surfaces use borders and tinted backgrounds before shadows. Dark hero evidence, screenshot wells, orbit marks, and the homepage demo use soft, large shadows to make the real interface feel physical.

### Shadow Vocabulary
- **Hero Demo Shadow** (`0 30px 80px -24px rgba(0, 0, 0, 0.92)` plus subtle glow): Use for the homepage notch demo only.
- **Editorial Screenshot Shadow** (`0 28px 75px rgba(33, 9, 2, 0.56)`): Use for product screenshots on warm dark heroes.
- **Orbit Mark Shadow** (`0 14px 35px rgba(0, 0, 0, 0.32)`): Use for competitor marks floating in the Alternatives orbit.
- **Warm Comparison Shadow** (`0 28px 70px rgba(33, 9, 2, 0.46)`): Use for the alternative detail `Versus` panel.

### Named Rules

**The Product Lift Rule.** Shadows belong to product evidence and comparison devices, not ordinary article prose.

## Shapes

The shape language is gently rounded and consistent. Buttons and standard cards use 8px. Screenshot wells and major comparison devices use 14px to 16px. Editorial chapter panels use 18px. The homepage photographic shell uses a 22px top radius. Chips and pricing tabs use pill radii.

Borders are hairline and structural. Avoid nested cards: when a mark or screenshot sits inside a larger panel, remove the extra tile if it would read as a card inside a card.

## Components

### Buttons
- **Shape:** Gently rounded rectangle (8px).
- **Primary:** Near-black on light pages, white on dark editorial heroes and CTAs.
- **Hover / Focus:** Background shifts only; warm CTA hover uses Cream Tint (`#fff0e7`) and focus uses a 2px visible coral-orange outline with 3px offset.
- **Secondary / Ghost:** White or transparent fill with hairline border, used for pricing and secondary CTA links.

### Chips
- **Style:** Pill shape with hairline border. Warm editorial docks use translucent white borders on dark heroes.
- **State:** Use text labels; do not rely on color alone.

### Cards / Containers
- **Corner Style:** Standard cards use 8px in the base skin and 16px in the warm editorial mosaics.
- **Background:** Cream-card or white on editorial hubs; editorial-panel for dark proof bands.
- **Shadow Strategy:** Cards are mostly flat. Hover may translate up 3px; screenshot/card media can scale slightly.
- **Border:** Hairline rule, warmed when the surface is in the editorial variant.
- **Internal Padding:** 1.125rem to 1.5rem for compact cards; clamp-based padding for major chapter panels.

### Inputs / Fields
- **Style:** Marketing pages mostly show app screenshots rather than live forms. When a field appears inside a product screenshot, preserve the screenshot as evidence rather than rebuilding it.
- **Focus:** Any interactive field must use the global visible focus rule.

### Navigation
- **Style:** Sticky 4rem header with brand left and compact links. Dark editorial pages tint the header with the editorial dark color. The homepage header rides directly over the photograph.
- **Typography:** Rounded brand wordmark, system-body nav links.
- **Mobile:** Links reduce spacing and wrap where needed; do not compress the Download pill until it becomes illegible.

### Feature Hub Spotlight and Chapters

The Features hub is not one continuous mosaic. The hero/header is a two-column headline/context row followed by one honest full-width notch capture in a subtle MacBook bezel. Lead the library below that with the dark dictation spotlight: large rounded display type, white copy on `editorial-panel`, a real dictation screenshot, and a peach action link. Follow it with job-based chapters. Movement and Mac-awareness chapters use three-up screenshot cards; the compact checks chapter uses tighter rows with a wide copy area and a fixed signal column.

### Feature Screenshot Wells

Feature pages use populated screenshot wells as proof. The hub signature is one genuine high-resolution notch capture, not layered screenshots. Workflow card captures preserve the original wide notch proportions, about 3.25:1, with `object-fit: contain`; do not crop them into fixed-height wells. Detail pages use a single large screenshot beside the hero copy, with a short caption aligned to the image.

Dictation remains evidence-led. Use the genuine model settings capture for the dictation spotlight until a valid retina live-dictation capture exists. Computer Use staging captures can inform composition, but a 640x210 JPEG is below the retina floor; the current PNG capture set remains the shipping authority, with most workflow captures spanning 1298-1388px wide. Never substitute a low-resolution, upscaled, or AI-reconstructed image as product evidence.

On dark feature detail heroes, captions and fact metadata must stay legible. Use raised white-alpha caption contrast rather than muted gray that disappears into the panel.

### Alternatives Utility Orbit and Lane Library

Alternatives pages use a Gojo-centered utility orbit. Competitor logos or monograms sit around the Gojo mark so the first viewport reads as comparison immediately. Detail pages use the `Versus` panel for the same job.

The Alternatives hub library is lane-based, not a flat card grid. Notch & Island Utilities and Focused Specialists sit on cream fields; Focused Specialists uses roomier row spacing and slightly larger explanatory type. Power Layers uses the sunset photograph under a warm dark overlay and peach action color, so it reads as a heavier automation material rather than a third identical card group.

## Do's and Don'ts

### Do:
- **Do** use ember red, coral orange, peach, cream, white, and near-black as the Gojo brand world.
- **Do** show real Gojo interface screenshots or comparison marks in the first viewport.
- **Do** use the 1322x418 `/screenshots/windows.png` capture as the Features hero authority until a better genuine high-resolution notch capture ships.
- **Do** keep editorial pacing varied with a dark dictation spotlight, job-based feature chapters, compact signal checks, three-lane comparison libraries, warm dark chapter breaks, screenshot wells, and comparison devices.
- **Do** preserve workflow card screenshot aspect ratios with containment rather than cropping.
- **Do** preserve the Alternatives lane taxonomy: Notch & Island Utilities, Focused Specialists, and Power Layers.
- **Do** keep dark screenshot captions and fact metadata readable against warm panels.
- **Do** keep AA contrast, visible focus states, reduced-motion behavior, and 390px no-overflow behavior.
- **Do** pair comparison colors with icons and words.

### Don't:
- **Don't** use blue or purple as Gojo brand accents.
- **Don't** return Features or Alternatives to white article monotony.
- **Don't** flatten the Alternatives hub into one undifferentiated card grid.
- **Don't** turn the Features hub back into one continuous mosaic.
- **Don't** rebuild the Features hero with layered tilted screenshot crops, sticky-note decoration, low-resolution captures, upscaled images, or AI-reconstructed product evidence.
- **Don't** leave screenshot wells empty on feature pages.
- **Don't** use decorative numbering where the content already has headings, marks, or facts.
- **Don't** add CTA eyebrows when the CTA headline and actions are already visible.
