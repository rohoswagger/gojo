# Gojo SwagUI ownership audit

Read-only source audit of `/Users/rohoswagger/Documents/personal_proj/gojo/gojo/web` on 2026-10-16. Source files were read while other agents were active. No repository files were changed. No browser session, package selection, registry download, or dependency installation was performed.

throughput checkpoint: n/a, read-only investigation

Investigation checklist followed:

1. Route through the **how** skill. For motivation questions, also route through the **why** skill.
2. Throughput checkpoint stays one line: `throughput checkpoint: n/a, read-only investigation`.
3. Produce the `how`-shaped output (Overview / Key Concepts / How It Works / Where Things Live / Gotchas), or a recommendation with a tradeoffs table if the request is a decision between alternatives.
4. Apply the **unslop** skill to the reply.

## Overview

The site already has a small local SwagUI-derived component set. Its actual page use is much narrower than the file inventory suggests. `GojoFooter` delegates rendering to `SiteFooter`, and alternative detail pages use `Section`. None of the six modules in `components/ui` is currently reachable from an App Router page/layout entry point. The copies of `SiteNav`, `FaqAccordion`, `CtaBand`, `HeroCentered`, `FeatureGrid`, and `PricingTiers` are unconsumed. This was checked with both import searches and a read-only local TS/TSX import graph covering all 10 app entry files.

The best next change is to give the existing local components real ownership of controls and shared JSX while retaining the approved page markup, selectors, and CSS. A larger rewrite of the HTML generators does not earn its cost here.

## Key concepts and data shape

| Shape | Existing owner | Reuse implication |
| --- | --- | --- |
| Header link `{ href, label }` plus home-dependent hrefs | `lib/site-header.ts:4-17` | One link list already feeds JSX and HTML-string headers. Preserve it. |
| Footer `{ title, links: { label, href }[] }` | `components/gojo-footer.tsx:14-41` | It derives sitemap links from feature/alternative content. `SiteFooter` should keep owning markup. |
| Feature `{ slug, name, tagline, what, useful, details, caveat, related }` | `lib/features.ts:9-23` | Feature route bodies remain HTML strings. Palette/class improvements can reach them without React conversion. |
| Alternative `{ slug, name, category, officialUrl, officialFacts, bestFor, gojoFit, tradeoff, relatedComparison }` | `lib/alternatives.ts:13-25` | Detail route already has typed JSX composition. This is the safest place for an article CTA adapter. |
| Comparison cell union `yes`, `no`, `unknown`, `text` | `components/comparison-table.tsx:12-28` | Keep its explicit meaning and visible words. Generic Card conversion offers no benefit. |
| Pricing tab `{ id, controls, name, device }` | `components/pricing-tabs.tsx:16`; `app/page.tsx:108-111` | Existing ids and panel associations can stay public while Radix owns the state/keyboard behavior. |
| Preview option `{ id, label, icon, image, width, height, alt }` | `components/product-preview.tsx:8-13` | Keep current pressed-button group and image dimensions. Swapping the button element is sufficient. |
| FAQ `{ question, answer }` | `app/page.tsx:120-126` | Native details support independent expansion. A single accordion would change behavior. |

## How it works

`components.json` declares shadcn's schema, `new-york`, Tailwind v4 CSS, React Server Components, TSX, and the normal local aliases. It contains no `registries` mapping or SwagUI URL. `package.json` has the already installed `radix-ui`, CVA, Tailwind, lucide, and motion packages. SwagUI provenance is indicated by local comments and `--ease-swagui`; there is no recorded registry configuration to reproduce the copies from this repo alone. Use the local files for this work. Do not invent a registry URL or install a replacement package.

Pages and content providers remain server components/modules. `Section`, `SiteFooter`, `GojoFooter`, `GojoHeader`, `Button`, and `Card` do not contain `use client`. `Button asChild` can preserve an anchor or Next Link without creating nested interactive controls. `Tabs`, `Accordion`, `Sheet`, the custom pricing controller, and the product preview are client components. Passing rendered server children into a small client control does not require converting the whole page to a client component.

`CtaBand` and `FaqAccordion` themselves are server-compatible wrappers, but both import client `Reveal`. Reusing them as written adds motion and hydration around their content. `SiteNav` is entirely a client component because it includes the Sheet menu. None of those wrappers is currently in the route graph.

Three route families still render trusted local content with `dangerouslySetInnerHTML`. Feature hub, feature detail, and alternatives hub call the HTML-string builders in `lib/features.ts` and `lib/alternatives.ts`. Those builders call `siteHeaderHtml`, which shares link data with `GojoHeader` but separately emits markup. A React component cannot become the owner of that existing string merely by adding `data-slot` attributes. Preserve this boundary for the current scope. The JSX blog block renderer can adopt shared Buttons for real CTA anchors without rewriting its text or tables.

## Where things live

| Component or system | Actual route use | Safe reuse opportunity |
| --- | --- | --- |
| `components/ui/button.tsx` | None | Wrap existing React download/purchase anchors with `Button asChild`. Preserve hrefs, classes, analytics attributes, and line wrapping. Use Button for the preview's existing actual button controls. |
| `components/ui/tabs.tsx` | None | Replace custom pricing state and keyboard handling behind the existing `PricingTabsProvider`, list, panel API. Keep current class names and IDs. |
| `components/section.tsx` | Alternative detail only | Keep article widths and spacing centralized here or in an explicit article variant. Do not put the homepage gallery into the default 75rem/large-padding wrapper. |
| `components/site-footer.tsx` | All routes through `GojoFooter` | Already genuine ownership. Theme its semantic tokens and preserve sitemap data. |
| `components/site-nav.tsx` | None | Adapt it to the existing inline/wrapping Gojo header contract before delegation from `GojoHeader`. Its current mobile Sheet menu is a different experience. |
| `components/cta-band.tsx` | None | A small nonanimated article variant could own the alternative detail CTA. Its current centered card, inner wrapper, glow, padding, and arrow do not match existing detail markup. |
| `components/faq-accordion.tsx` | None | Optional for a genuinely new single-open FAQ use case. Keep native homepage details and expanded editorial FAQs in this task. |
| `components/ui/card.tsx`, badge, sheet | None | Do not force them into article prose, semantic tables, or genuine screenshot frames to increase a usage count. |

The comment at `app/globals.css:503-507` says alternatives compose Section, FaqAccordion, and CtaBand. Current `app/alternatives/[slug]/page.tsx:164-193` instead renders custom expanded FAQ articles and a custom Section CTA. The comment is stale evidence, not proof of adoption.

## Tokens and approved homepage constraints

There are three styling contracts. `globals.css:10-33,112-136` defines neutral SwagUI-style semantic variables. `skin.css:16-66` defines separate surface/ink/Gojo accent/font/layout variables. `home.module.css:1-17` applies a beach palette scoped to the homepage. `marketing-heroes.css` applies warm editorial hero colors with additional literal values. This split explains why new UI components would retain neutral dark buttons and a blue ring on editorial pages unless deliberately themed.

Bridge semantic colors to the actual theme where the component is rendered. Alias foreground/background/card/border/muted text/ring and intended primary/secondary pairs together. A root-only alias is insufficient when a child theme later overrides the referenced variables, because inherited custom-property values have already resolved their root references. Define the semantic pairs on the theme wrapper too. Keep `--muted` as a background fill; the homepage currently uses that name for a text brown, while SwagUI TabsList expects `bg-muted` to be a faint fill.

Keep the homepage local Instrument Serif used by the hero and final CTA, including italic display copy. Other current headings intentionally use the rounded display stack. Avoid globally setting all headings to the serif solely to get consistency. `app/layout.tsx:5-7` also has an outdated no-webfonts comment because the homepage now loads a local serif.

Exact homepage constraints are visible in `home.module.css`. The hero uses its own brown CTA at lines 35-38. Screenshot card shape and layout are at 59-68. The selector has fixed media geometry at 43-46 and 44px controls at 48-52. Pricing styling depends on `.pricing-*` and `.plan-*` at 96-121. The footer has a direct-child rule at 135. Preserve these classes and element relationships when moving ownership. Default Button `whitespace-nowrap`, `shrink-0`, fixed heights, brightness hover, and active scaling must be reconciled with those existing controls rather than silently added.

## Two bounded implementation approaches

| Approach | Scope | Benefit | Cost or risk |
| --- | --- | --- | --- |
| A. Existing components own the current DOM | Theme the existing local controls. Adopt Button in JSX CTAs and preview controls. Put Radix Tabs behind the pricing wrapper. Adapt SiteNav to the current inline header contract and have GojoHeader provide its data. Keep Section and SiteFooter as the existing layout owners. Add an article CtaBand variant only if it preserves current markup. | Real component use with small call-site changes. Maintainers have one JSX implementation per control. Approved homepage selectors, screenshots, copy, and layout remain intact. | Needs explicit handling of CSS layer/focus conflicts and Radix panel mounting. HTML-string headers remain a second renderer sharing the same link model. |
| B. Replace selected JSX areas with SwagUI marketing blocks | Convert alternative detail CTA/FAQ plus homepage FAQ/final CTA/header to CtaBand, FaqAccordion, and current SiteNav, then add targeted style overrides. Leave HTML generators alone. | More prebuilt blocks become used with a smaller initial ownership refactor. | Changes DOM, spacing, mobile navigation, FAQ expansion rules, motion, and initial rendered content. The override burden is larger and the approved homepage becomes harder to protect. |

Recommend A. The actual problem is duplicated control behavior and independent theme decisions. A resolves both while retaining the approved experience. B would spend most of its effort undoing the generic block defaults. This recommendation follows Laziness Protocol by changing actual shared ownership rather than converting the whole generator system. Experience First keeps the stable screenshot selector, readable text, compact copy, and current mobile navigation intact. Type System Discipline keeps the existing typed records and comparison union rather than adding a second general page schema.

Implementation can stop after the theme bridge, real Button consumers, pricing behavior ownership, adapted JSX header ownership, and targeted article CTA if needed. A full Card/Accordion migration is unnecessary.

## Gotchas and accessibility findings

1. **Focus conflict before adopting Button or Accordion.** `skin.css:92-96` declares a brown outline but forces a white box shadow with `!important`. It is imported in the components layer. Button and AccordionTrigger apply utility-layer `outline-none` and Tailwind ring shadows at `ui/button.tsx:9,17` and `ui/accordion.tsx:38`. Source cascade analysis predicts that non-home controls can lose the brown outline while the white shadow replaces their visible ring. The homepage's unlayered scoped focus rule changes the outcome there. This is a source-derived risk, not a browser-measured failure. Fix shared focus ownership and verify it on both cream and white backgrounds.

2. **Sheet close has an undersized hit area.** `ui/sheet.tsx:78-80` gives the close button no padding or minimum size around a 16px icon. Make the actual close target 44px if Sheet is activated. Its icon already has accessible text.

3. **SiteNav same-page links do not dismiss the dialog.** `site-nav.tsx:78-93` renders plain anchors without SheetClose or controlled close state. Home anchor links can leave a modal open over the new destination. Both nav landmarks are also unlabeled, unlike current GojoHeader's `aria-label="Primary"`. Add labels and close behavior if this mobile mode is retained. The fixed-height Sheet content has no scrolling rule, which is a short-viewport risk once content grows.

4. **Reveal hides real content until JavaScript/in-view execution.** `reveal.tsx:19-35,50-55` emits an initial hidden opacity, even for reduced-motion users. The reduced variant still fades and preserves delay. A new CtaBand/FaqAccordion consumer would add this behavior. Keep critical article CTAs and FAQ text visible by default or remove the decorative wrapper in their plain/article variant.

5. **Tabs require behavior-preserving mounting.** Current pricing panels remain in HTML with `hidden`, including all checkout links, at `pricing-tabs.tsx:125-134`. Radix content normally unmounts inactive panels. Preserve the public IDs, aria-controls/labelledby, default Personal selection, Arrow/Home/End behavior, and hidden inactive content. Verify both checkout sets remain available where expected in the export. Do not use `forceMount` without also applying the correct hidden state.

6. **TabsContent removes its outline without a replacement.** `ui/tabs.tsx:85` uses `outline-none`. If a tab panel receives focus, preserve a visible focus indicator. Confirm the chosen panel/tab-stop behavior in the real browser.

7. **Skip-link coverage is structurally tested but incomplete semantically.** Alternative detail and downloads put `id="main-content"` on a hero section before the actual main landmark. The link still targets focusable content. Avoid moving or duplicating it accidentally while sharing headers. The existing verifier checks count, presence, and `tabindex`, but does not verify that the target is the main landmark or test focus visibility, keyboard behavior, contrast, menu dismissal, reduced motion, or target size.

`SiteFooter` already gives links 32px minimum height, above a 24px minimum but below a 44px comfort target. This is a possible usability refinement, not a claimed conformance failure. Existing comparison cells pair yes/no/unknown icons with words and should retain that accessible meaning.

## Validation and limits

Source and import graph findings are verified against the local files. No runtime accessibility or pixel-parity verdict is claimed. Prove It Works shaped that distinction.

After implementation, use the existing `npm run lint`, `npx tsc --noEmit`, `npm run build`, and `node scripts/verify-funnel-analytics.mjs`. The build runs marketing-link and structural-accessibility checks. `verify-marketing-links.mjs` requires exact header href order and distinguishes home `#features`/`#buy` from other routes. Preserve `data-funnel-*` attributes when wrapping anchors with Button. Browser verification must cover homepage desktop/mobile parity, stable preview geometry while selecting all four views, pricing keys and focus, footer/link readability, editorial focus visibility, and any retained Sheet interactions. Other agents can perform those checks in the shared implementation lane.
