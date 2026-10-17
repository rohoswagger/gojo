# Accessibility and readability review

Scope is the Gojo landing page and shared marketing navigation, footer, landmarks and skip navigation. The user explicitly requested a visible beach behind the hero with less text and larger text. No solid hero-copy panel was added.

## Changes

- Hero copy is one short 21 px sentence. Both "3 days free" and "Yours for $9.99 once" are 21 px, with the price emphasized. The photograph remains visible and the copy background is transparent.
- Selector labels grew from 11 px to 15 px. The trial offer grew from 11 px to 21 px. Supporting card, pricing and FAQ text is generally 16–17 px. Descriptions were trimmed rather than padded.
- Header navigation and main controls have 44 px minimum targets. All navigation links remain available on phones. The header is in normal flow and expands with text size.
- Shared skip links lead to real focusable content. Duplicate main landmarks were removed. Footer columns have semantic 13 px headings and 32 px link targets. Focus has contrasting dark and light rings.
- Pricing tabs, price rows, inline links and small cards reflow at narrow widths with doubled text. Round buttons and the fixed screenshot frame remain.
- A dictation link now has a visible underline. Named groups use appropriate roles. Small brown text was darkened where the earlier contrast review found failures.

## Evidence

`pnpm build` passes, including existing marketing-link checks and the new exported accessibility-structure check. All 61  exported HTML pages have one main landmark, a unique focusable skip destination, a skip link, a page heading and alternative-text attributes on images. The check runs during future builds through `web/scripts/verify-accessibility.mjs`.

Full lint has zero errors and the same two existing next/no-img-element warnings in night-shift-comparison.tsx. The telemetry contract check still passes.

axe-core 4.10.3 was run in the T3 in-app browser on the homepage, Features, Alternatives, Downloads and Blog. Those five scans report zero definite WCAG A/AA violations. The scanner leaves photo/gradient contrast unresolved. Its earlier link-in-text finding was fixed and the two generic-group ARIA questions were resolved.

A canvas analysis reconstructed the actual beach image, CSS crop and gradient, then sampled the background under text bounds. At the checked desktop viewport, the lowest sampled hero contrast was 5.25:1 for the lifetime offer. The free-trial line was 5.65:1. The headline's italic line was 6.85:1 and supporting copy 9.21:1. These are viewport-specific samples, not certification across arbitrary future photographs or layout changes.

T3 checks confirmed all four screenshot selections retain the same stage, hero and next-section position. Pricing tabs respond to ArrowRight and Home. Enter on the skip link moves focus to main-content. Responsive checks covered 320,390 and 768 px. A 320 px reflow check with all text doubled found no overflowing content and no header/headline overlap.

## Limits

The automated Features and Alternatives scans still mark photographic/gradient contrast for manual review. No claim of full WCAG conformance is made. T3's saved-screenshot operation continues to fail on local pages, so the review relies on live browser inspection, computed layout/contrast checks and exported artifacts. Production deployment and production PostHog delivery were not performed.

References are the [W3C contrast criterion](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) and [target-size criterion](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html).44 px targets are a usability choice; the AA minimum criterion includes 24 px targets and spacing exceptions.
