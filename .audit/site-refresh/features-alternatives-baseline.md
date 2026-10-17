# Feature and alternative audit

This is a read-only audit of the Next website under `/Users/rohoswagger/Documents/personal_proj/gojo/gojo/web`. The approved homepage is the design reference. No native app files or website source files were changed. Browser and SwagUI inspection belong to the leader's lane and were not repeated here.

Throughput checkpoint. n/a, read-only investigation.

## Overview

The page families already have useful content structures. Keep the feature chapters, genuine screenshot library, three alternative lanes, and explicit comparison cells. Their shared hero stylesheet now overrides the beach identity with an older cream-sheet treatment. The largest improvement is to replace that override with one coastal treatment, then repair concrete proof, navigation, and tracking defects.

The evidence below comes from current source and local exported HTML. It does not establish what is deployed at trygojo.com or which native app release is current.

## Key concepts

- `web/lib/features.ts` owns both the feature hub and all ten feature detail HTML templates. `web/content/features.json` supplies the copy.
- `web/lib/alternatives.ts` owns the twelve-item hub, metadata, schema, and data access. Its older `alternativeArticleBody` export has no caller in `web`.
- `web/app/alternatives/[slug]/page.tsx` owns the actual twelve alternative detail pages. Styling the older HTML template will not change these routes.
- `web/lib/comparison.ts` supplies the eight comparison rows. `web/components/comparison-table.tsx` renders an explicit yes, no, unknown, or text cell.
- The hub and detail route shells set `data-gojo-editorial="warm"`. `globals.css` imports `skin.css` and then `marketing-heroes.css` into the same CSS layer. The latter stylesheet is the final hero override.
- `home.module.css` scopes the approved beach design to the homepage. Its local font variable is attached only by `app/page.tsx`.

## Material findings

| Priority | Finding and evidence | Smallest safe change |
| --- | --- | --- |
| High | The four page types lose the beach hero. `marketing-heroes.css:202-234` gives `.feature-shell` and `.alternative-shell` a flat `#fdf6ee` field, replaces photographic pseudo-elements with radial gradients, and suppresses the original hero image. The earlier hub-specific rules at lines 2-20 do the same for Alternatives. The homepage uses the actual beach at `home.module.css:30`. | Replace the cream-sheet rules in `marketing-heroes.css`. Apply the approved cream sky wash over `/assets/bg.webp` to the four scoped hero containers. Keep copy directly on the photograph and keep the genuine screenshots or comparison device visible. Do not append another override layer. |
| High | Interior hero typography does not inherit the approved Instrument Serif. `marketing-heroes.css:82-90` and `:218` impose 10ch, 600-weight headings. `skin.css:1107-1117` supplies rounded type. The font is loaded only in `app/page.tsx:12-19`, while the homepage uses it at `home.module.css:32`. | Have the shared layout expose the existing locally hosted Instrument Serif variable. Apply serif only to the scoped hero h1 and closing CTA headline. Keep feature, chapter, comparison, and article headings native rounded. Relax the 10ch limit so names such as Karabiner-Elements do not produce unnecessary towers of text. |
| High | Every direct download CTA in this slice misses the existing funnel hook. I parsed 24 local exported feature and alternative routes. All 26 direct download anchors lacked `data-funnel-event`. `funnel-analytics.tsx` listens only to `a[data-funnel-event]`. Source examples are `features.ts:168,208`, `alternatives.ts:226,240`, and `alternatives/[slug]/page.tsx:186`. | Add `data-funnel-event="download_cta_clicked"` and bounded placement values such as `feature_hub_hero`, `feature_detail_end`, `alternatives_hub_hero`, and `alternative_detail_end`. Preserve direct download destinations. Do not mark the `/#buy` navigation links as checkout events because the analytics handler restricts those events to Stripe destinations. |
| High | The Alternatives hub's main comparison jump is broken. `alternatives.ts:226` links to `#alternatives-library`, but the library section at `:240` has only a class and `aria-labelledby`. Current exported HTML confirms no target for that hash. | Add `id="alternatives-library"` to the existing library section. Extend the existing link check to cover same-page hashes. |
| High | Feature screenshots make claims the local design authority explicitly disallows. The hub alt text and caption at `features.ts:208` claim real or live window previews. `DESIGN.md` says the current window capture shows app choices, layouts, and shortcuts, with an empty preview region. The detail mapping at `features.ts:60` also uses `windows-tab.png` instead of the approved `windows.png`. | Use `/screenshots/windows.png` for both hub and detail. Describe only visible app choices, layout controls, and shortcut labels. Keep supported product capability copy separate from claims about what the screenshot proves. |
| Medium | Buttons remain rectangular on feature pages and alternative details. `.btn` is 8px in `skin.css:222-239`. Only the Alternatives hub hero and header get pill rules in `marketing-heroes.css:46-52,209`. The homepage uses pill buttons throughout at `home.module.css:35,117`. | Set pill radius, at least 44px targets, 16-17px labels, and wrapping inside the shared warm marketing scope. Match cream, ember, and brown action materials to their background. |
| Medium | Dense comparison and guide copy is markedly smaller than the approved homepage. Alternative lane category labels are 11px, body copy 13px, and action labels 12px at `skin.css:4728-4759`. Comparison cells shrink to 14px on mobile at `:3852-3855`. Feature card copy is 14px and action copy is 13px at `:2526-2538`. | Raise lane and card body text to 16px, categories to 14px, and actions to 15-16px. Keep 16px comparison cells on mobile. Increase room instead of reducing type. Use 20-21px hero support text and readable trial terms, with 44px actions. The exact contrast and reflow results need the leader's browser pass. |
| Medium | Four feature details lead with decorative orbits rather than the real interface. `featureArticleBody` falls back to `.feature-detail-generated` at `features.ts:167` for calendar, battery, camera, and shortcuts. The only current screenshot mappings cover six features. | Avoid presenting these drawings as proof. Use one existing genuine whole-workspace capture with a caption that accurately identifies it, or a compact text treatment and link to the full workspace. Do not invent screenshots or label unrelated captures as these features. A new feature-specific capture requires the real capture workflow. |
| Medium | The main landmark omits the page title and hero on all 24 exported routes. `#main-content` is a focusable section before the body `main`. Source examples are `features.ts:168,208`, `alternatives.ts:226,240`, and `alternatives/[slug]/page.tsx:76,104`. Existing accessibility checks accept this structure. | When touching the templates, let one `main id="main-content" tabindex="-1"` include the hero and body, with the shared header outside. Preserve one main landmark and the skip link. The impact on landmark navigation is a supported structural concern, not a tested screen reader failure. |
| Medium | Product positioning is inconsistent across comparisons. `PRODUCT.md` says Gojo is a complete Mac upgrade and should avoid positioning itself as a smaller alternative. `alternatives.json` repeatedly calls it smaller, narrower, or fewer controls. `alternatives/[slug]/page.tsx:126` says six tools while the feature hub exposes ten feature entries and treats local dictation as flagship. | Keep the factual specialist tradeoff, remove unsupported breadth rankings, and state Gojo's concrete built-in workflows. Replace the six-tool count with wording that does not imply a complete inventory. Do not change competitor facts from memory. |
| Medium | Source and reading links lose their visible underline on Alternative bodies. `skin.css:3187-3195` applies `text-decoration:none !important` to all body links, including the official source link whose own rule requests an underline at `:3867-3870`. | Limit the no-underline treatment to whole linked cards and buttons. Restore underlines to prose, source, and reading links, with a visible focus state. |

## How it works

The feature hub and detail routes use `dangerouslySetInnerHTML` with server-built strings. Their escaped content data is not a reason to rewrite them as React components for this design task. The alternative detail pages already use React components, `Section`, `Versus`, and `ComparisonTable`. Shared styles and consistent attributes can align these implementations without adding dependencies or another rendering abstraction.

Existing structures worth keeping include genuine high-resolution feature captures, the dictation spotlight, job-based chapters, compact utility rows, three comparison lanes, the Power Layers photographic field, responsive two-column comparison rows, explicit unknown facts, text plus icons for yes and no states, and reduced-motion rules.

The current Alternatives hero is an index, not the Gojo-centered orbit described in `DESIGN.md`. The twelve recognizable logos still provide comparison context. Changing the hero's identity and typography is sufficient for this pass unless the leader's SwagUI and browser review establishes a clear reason to rebuild the hero device. Restoring an orbit adds layout risk without repairing the concrete broken link, tracking, or readability problems.

## Where changes belong

| Owner lane | Files | Scope and stop condition |
| --- | --- | --- |
| Shared coastal system | `web/app/marketing-heroes.css`, the smallest necessary scoped edits in `web/app/skin.css`, `web/app/layout.tsx`, `web/app/page.tsx` | Replace the contradictory hero overrides. Expose the existing serif font once. Match beach, cream sky, warm ink, rounded actions, reading sizes, focus, reduced motion, and wrapping. Homepage remains visually approved. One owner should hold these shared files. |
| Feature templates | `web/lib/features.ts` | Correct window proof text and asset. Add native image dimensions and download tracking. Remove repeated filler, use honest fallbacks, and repair main landmark if the shared layout change is included. All ten detail routes and the hub retain their content and working links. |
| Alternative templates | `web/lib/alternatives.ts`, `web/app/alternatives/[slug]/page.tsx` | Repair the library anchor. Add download tracking, trim repeated framing, preserve comparison schema and data, and repair landmarks if included. Leave the unused `alternativeArticleBody` alone unless the leader deliberately includes its deletion. |
| Editorial fact review | `web/lib/comparison.ts`, `web/content/alternatives.json` | Separate current official verification from styling. Keep the explicit unknown state. Do not update the date unless the facts were actually rechecked. This lane should be handled by the leader or its designated researcher. |
| Website verification | `web/scripts/verify-marketing-links.mjs`, `web/scripts/verify-accessibility.mjs`, `web/scripts/verify-funnel-analytics.mjs` if needed | Reuse existing scripts. Add checks for internal fragment targets and tracked direct downloads. Check one main containing h1 if landmark repairs are made. Do not add dependencies or broad snapshot tests. |

## Verification evidence

I parsed current local exports under `web/out` with the installed `node-html-parser`. The files inspected were last modified at approximately `2026-10-16T22:07:21Z`.

- There are 24 exported routes in this slice, two hubs, ten feature details, and twelve alternative details.
- All 26 direct download links on those routes lack the funnel event attribute.
- The Alternatives hub has a missing `#alternatives-library` target. The other same-page hashes in this slice resolve.
- All 24 `main` landmarks omit the route h1. All skip targets exist and are focusable sections before `main`.
- `sips` reports `windows.png` at 1322 by 418, `windows-tab.png` at 1370 by 434, media at 1308 by 392, clipboard at 1388 by 394, shelf at 1298 by 392, dictation-models at 920 by 342, and settings-nightshift at 1362 by 1178. Detail templates use generic 1200 by 760 intrinsic dimensions and card templates use 900 by 560, despite different real ratios. Current CSS explicitly sets contained or auto-height rendering, so distorted final rendering is not established here. Native dimensions still avoid misleading reserved space.
- `rg` found no caller of `alternativeArticleBody` in `web`. The live route imports only its data, schema, and metadata functions.

The leader should validate all four page families at desktop and 390px, plus 200 percent text reflow, after the shared CSS change. Include a feature with a wide screenshot, display settings with a tall screenshot, one feature without a specific capture, a long competitor name, reduced motion, visible keyboard focus, and the comparison table on mobile. Run lint, typecheck, production build, existing link and accessibility checks, and the existing funnel verification where its configuration permits. A local analytics event can be inspected with a configured non-local hostname because the client intentionally skips localhost.

## Gotchas and factual limits

`comparison.ts` embeds third-party prices, trials, minimum OS versions, and device counts. The shared content date is `2026-08-10`. I did not verify external official pages and make no claim that these values remain current. In particular, `alttab.trial` says `14 days on Pro features` at line 75, while the corresponding content facts describe an open-source window switcher. This mismatch warrants official-source review. It is not evidence here that an AltTab Pro product exists or does not exist.

The local design and capture guide disagree about what `windows.png` currently depicts. `DESIGN.md` is explicit that its preview region is empty. Use this current authority when writing screenshot captions. The capture guide describes the desired future shot, and still calls `windows-tab.png` an older 1x file. Its present dimensions alone do not establish capture density.

The comparison footer's phrase `checked` and its date are rendered claims. Do not advance that date as a side effect of styling. Signing, notarization, automatic updates, actual release version, and production availability were not verified in this audit.

Laziness Protocol shaped the recommendation to replace the final contradictory stylesheet and reuse existing renderers. Experience First shaped the recommendation to spend space on readable text and honest screenshots before rebuilding decorative devices. Type System Discipline shaped the recommendation to preserve the existing discriminated comparison cell and explicit unknown state. The matching leaf skills were read in this session. Unslop and Technical Writing were applied to this report.
