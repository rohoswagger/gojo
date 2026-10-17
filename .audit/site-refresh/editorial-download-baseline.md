# Editorial and download audit

Read-only source audit completed on 2026-10-16. No source files or browser state changed.

Throughput checkpoint is n/a for this read-only investigation.

## Overview

The blog index, 32 article pages, download page and 404 page still inherit the older white, purple-accent site skin. The homepage's cream, brown and ember variables only exist beneath its CSS-module `.home` root. The result is a source-confirmed design discontinuity when a reader leaves the homepage. Browser appearance remains unverified in this slice.

The release details need a separate factual correction during the visual work. The download page advertises 1.4.0 and an old fixed checksum while downloading the mutable latest alias. The repository's newest appcast record is 1.5.1. A safe visual refresh must not carry the old checksum into a more prominent card.

The smallest useful change is a shared warm marketing frame, small route-specific layouts, and the existing article renderer. Keep article content, URLs, metadata and the static-export architecture intact unless a factual error is identified below.

## Key concepts

- `web/app/home.module.css` lines 1-18 define the approved cream, charcoal, brown and ember palette. Lines 32-40 define the editorial serif hero, larger lede and pill action. The native rounded heading family continues at lines 50-65. These rules do not reach sibling routes.
- `web/app/blog/page.tsx` renders `_hub.json`. `web/app/blog/[slug]/page.tsx` renders a `BlogPost` from the fixed slug registry in `web/app/blog/lib.ts`. `ArticleBlocks` renders answer boxes, jump links, paragraphs, tables, FAQs and CTAs.
- `web/app/skin.css` supplies these routes' old visual system. Its global accent is purple `#4a46cf` at line 31. `web/app/globals.css` also retains blue brand tokens at lines 23-24. The warm feature/alternative overrides require `data-gojo-editorial="warm"`, which the blog routes do not set.
- The existing SwagUI `Button` already supports `asChild` and pill shapes. `Section` supports a narrow width. Reuse these where an action or section genuinely benefits. The article body already has the right semantic structure and reading measure.

## Concrete findings

| Priority | Source evidence | Effect and smallest correction |
| --- | --- | --- |
| High | `web/app/downloads/page.tsx` lines 6-16, 43-45, 95-96 and 132-133. `appcast.xml` lines 8-42. | Version, file size, description, JSON-LD and expected hash belong to 1.4.0, while the download href resolves through the latest alias. Remove fixed claims until tied to a verified artifact, or populate a single release record from verified release metadata. Do not replace the hash from a guess. |
| High | `web/app/downloads/page.tsx` line 67 says nothing else is requested up front. `Gojo/components/Onboarding/OnboardingView.swift` lines 32-103 presents optional camera, calendar and reminders access before Accessibility. | Installation instructions contradict source behavior. Say that setup explains each permission and optional features can be skipped. Describe Accessibility's role without the incorrect exclusivity claim. |
| Medium | Blog index root at `web/app/blog/page.tsx` line 40. Article root at `web/app/blog/[slug]/page.tsx` line 75. Base colors at `web/app/skin.css` lines 17-35. | Both routes retain white ground, black ink and purple links. Add a shared warm root that sets the relevant skin and SwagUI tokens to the approved palette. Keep body reading surfaces cream and links ember. |
| Medium | `web/app/skin.css` lines 1107-1127, 1598-1684. | Blog hero is rounded system type at up to 52px. Cards have 17px headings, 14px summaries and 12px metadata in thin white 8px tiles. Use a restrained serif index title, 20-24px rounded card titles, 16-17px summaries, 13-14px metadata and warm surfaces. Preserve chronological/source content instead of manufacturing a featured story. |
| Medium | `web/app/blog/page.tsx` lines 49-85, article lines 84-111, and `web/app/blog/lib.ts` block union. | Neither template renders a product screenshot. The block model has no media variant. Add one real product capture to the index introduction and a compact template-level product figure or CTA for articles. Avoid a broad media schema migration just to add the same product image to 32 articles. Use the existing screenshot files and their native aspect ratios. |
| Medium | `web/app/skin.css` lines 1158-1173, 1388-1436. | Article body is already 16px with a 44rem measure, but CTA copy is 15px, trust copy 12px and the CTA is a gray 8px card. Keep the quiet reading layout. Increase reading copy to 17-18px, use 16px CTA copy and a rounded warm CTA with a clear pill action. Keep headings native rounded beneath the serif article title. |
| Medium | `web/app/downloads/page.tsx` lines 80-108. | Skip-link destination is a section around the hero, while the `main` begins below the hero. Move one `main#main-content` around the complete download task so assistive navigation reaches the heading and action as one landmark. The current structural verifier counts main and destination separately, so it will not catch this mismatch. |
| Medium | `web/app/not-found.tsx` lines 11-32 and `web/app/skin.css` lines 266-312. | 404 reuses the retired generic home hero, including purple `glow`, black 8px action and small 13px secondary links. Give it a small warm route frame, serif page title, one obvious home action and clear feature/blog links. A 404 does not need an oversized decorative numeral or product gallery. |
| Low | `web/app/skin.css` line 1625 fixes the blog grid minimum at 20rem, while wrap adds 40px of gutter on small screens. | At a 320px viewport, the grid needs at least 360px. This is a source-derived overflow risk. Use `minmax(min(100%, 20rem), 1fr)` or a one-column mobile rule and verify at 320px and 390px. |
| Low | `web/app/layout.tsx` lines 5-7 says there are no webfonts. `web/app/page.tsx` lines 2 and 12-17 loads Instrument Serif locally. | Delete or correct the stale comment when moving the existing font variable to a shared marketing scope. Reuse the existing licensed local files. |

## Release facts and limits

The following facts are available from the repository without a network request.

| Fact | Evidence |
| --- | --- |
| Newest listed public feed version is 1.5.1. | `appcast.xml` lines 9-13. |
| The record is dated 2026-09-04 and requires macOS 14.0. | `appcast.xml` lines 10 and 13. |
| Its immutable artifact URL is `https://downloads.trygojo.com/Gojo-1.5.1.dmg`. | `appcast.xml` line 39. |
| Its listed size is 17,217,841 bytes. | `appcast.xml` line 41. This is 17.2 decimal MB or 16.4 MiB if display rounding is needed. |
| Changelog and project marketing versions agree with 1.5.1. | `CHANGELOG.md` line 10. `Gojo.xcodeproj/project.pbxproj` lines 1399, 1424, 1600 and 1655. Local tag inventory includes `v1.5.1`. |
| Public releases upload both an immutable versioned key and mutable `Gojo.dmg` key. | `scripts/release.sh` lines 411-416. |
| Release script prints a SHA-256 at release time. | `scripts/release.sh` lines 393 and 466. It does not write a website release manifest. |
| No 1.5.1 SHA-256 is available in the tracked release facts read for this audit. | `appcast.xml` stores a Sparkle EdDSA signature and byte length, not SHA-256. Repo search found the displayed 1.4.0 hash only in the download page. |

The appcast proves the repository's release record. It does not prove which bytes the live `Gojo.dmg` alias serves today. The existing hash could still be correct for the old immutable 1.4.0 artifact. It cannot safely validate an evolving latest alias.

For this bounded site update, the lowest-risk option is to retain the latest download alias, remove fixed version, size and hash claims, and retain the Developer ID and Apple notarization explanation. If versioned details are required, use a verified immutable artifact with its exact size and SHA-256. A later release-manifest improvement can automate that pairing, but it is additional release-tooling scope.

Other copy corrections are justified by source.

- Replace "Signed and notarized by Apple" with "Developer ID signed and Apple notarized". The release script signs with the developer certificate and submits to Apple's notarization service.
- Replace "Dictation runs on device" with "Local dictation stays on your Mac" or equally explicit wording. `CHANGELOG.md` lines 44-46 records optional OpenRouter transcription. Keep the local-first benefit while accurately describing choice.
- Prefer "Automatic updates included" to "Updates install themselves". `Gojo/components/Settings/SoftwareUpdater.swift` lines 40-59 exposes user controls for automatic checking and downloading. The repository does not establish unconditional installation behavior.
- The homepage JSON-LD also hardcodes `softwareVersion: "1.4.0"` in `web/app/page.tsx` line 61. Root owns that file and should apply the same release-fact decision there.

## Metadata and content validation

A Python source check loaded all 32 JSON article files and `_hub.json`.

- Archive slugs match the 32 files, with no duplicates.
- Each post canonical and `og:url` matches its expected `/blog/{slug}/` URL.
- Jump-nav fragment links match heading IDs in the same post.
- All 32 posts have an OG image. All currently use the existing `/assets/og.jpg`.
- The current templates preserve article authors, robots, canonical, published and modified times, JSON-LD and Twitter large-image fallbacks. Preserve this behavior during styling.

No metadata defect was found in those checks. The duplicated source slug registry is a maintenance cost, but refactoring it is unnecessary for this visual task.

## Smallest implementation plan

1. Add one shared beach/cream marketing root for blog, downloads and 404. Reuse the local Instrument Serif font variable. Set warm skin and SwagUI tokens in that root so buttons and existing article blocks agree. Keep page-specific selectors scoped so feature and alternative work can proceed independently.
2. Refresh the blog index and article template. Use a photographic or cream-washed introduction with one genuine product capture on the index. Give articles a serif title, native rounded section headings, larger reading copy and warm table/callout accents. Preserve the narrow reader, FAQ text, source facts, internal links, metadata and JSON-LD.
3. Rebuild the download page around one main landmark and the clear download action. Add a real screenshot at natural proportions. Keep installation, permissions and trial details concise. Apply the safe release-fact decision above before displaying verification details.
4. Replace the 404's generic hero classes with a small matching warm layout and clear recovery links. Keep it useful and short.
5. Use the existing SwagUI `Button asChild` for primary actions and `Section` only where it simplifies the route. Override the large button to at least 48px high and about 17px text. Do not wrap normal article paragraphs in extra cards or add dependencies.
6. Run lint, TypeScript, the existing build/link/accessibility checks and actual T3 review. Include `/blog/`, a long table article, a short comparison article, `/downloads/` and `/404.html`. Check desktop, 390px and 320px widths, keyboard focus, skip-link destination, anchor links, download href, native screenshot ratios and reduced motion.

## Principles applied

Laziness Protocol shaped the recommendation to keep the current article data and renderer, add one shared warm scope, and avoid a media-schema or release-tooling rewrite. The leaf skill was read at `/Users/rohoswagger/.codex/skills/principle-laziness-protocol/SKILL.md`.

Experience First shaped the choice to prioritize readable article text, accurate install guidance, a clear download action and useful 404 recovery. The leaf skill was read at `/Users/rohoswagger/.codex/skills/principle-experience-first/SKILL.md`.

The Poteto investigation and how workflows shaped this read-only ownership map. Unslop shaped the concise factual copy recommendations and the decision to avoid decorating article prose with nested cards.

## Remaining risk

This slice did not inspect the browser, fetch a live release or calculate a binary checksum. Root owns T3 validation and the homepage. Many native app edits and several website edits already exist in the shared worktree. This audit did not change or revert them.
