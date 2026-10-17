# Site audit and coastal alignment

The approved homepage now supplies the visual system for feature, comparison, blog, download and error pages. Interior heroes use the beach photograph, Instrument Serif, cream surfaces, brown text and round actions. Real product screenshots retain their aspect ratios. Shared rules replace the conflicting hero stylesheet.

## Changes

- Shared design: `web/app/marketing-heroes.css`, `globals.css`, `layout.tsx`, `web/lib/coastal-font.ts` and `DESIGN.md`.
- Actual SwagUI consumers: Button in React navigation, preview and calls to action; Section in comparison detail and error layouts; shared SiteFooter. Static HTML generators keep their renderer and matching styles. The existing pricing keyboard controller remains; the unused Tabs modification was removed.
- Feature/comparison templates: proper main landmarks, working library fragment, honest screenshot captions, simpler utility cards, tracked direct downloads and wrapping comparison grids.
- Editorial/download/error templates: matching coastal heroes, real screenshots, focusable comparison-table scroll regions, accessible error title and verified release details.
- Facts: versioned Gojo 1.5.1 download, 17,217,841 bytes, independently verified SHA-256; Raycast seven-day trial; AltTab free core/paid Pro distinction. Privacy copy now distinguishes local dictation from optional cloud transcription. Other competitor prices were not comprehensively refreshed.
- Regression prevention: `web/scripts/audit-site.mjs` runs in the production build and checks every exported route, internal target, local image, landmark, canonical and direct-download annotation.

## Evidence

- Production build passes, including marketing links, structural accessibility and the full route crawl: 61 HTML files, 55 tracked direct-download actions, 122 rendered SwagUI Button slots, zero static issues.
- T3 browser: all 61 files at 320px and 1440px (122 checks), zero reported axe WCAG violations or detected horizontal overflow. Eight representative interior routes also pass 320px with text enlarged to 200%. Intentional comparison-table scrolling remains available.
- Homepage: screenshot frame and control positions remain identical across Windows, Clipboard, Files and Music. Hero copy background remains transparent. Both trial/lifetime offers compute to 21px.
- Real keyboard checks: pricing ArrowRight and Home update selection and focus; Enter on Skip to content focuses main-content.
- TypeScript, funnel analytics and lint pass. Lint retains two existing Next image warnings in `night-shift-comparison.tsx`.
- Independent source/export review confirmed release checksum and found the privacy-copy issue, which was corrected.

Detailed route and browser results are in `verified-routes.json` and `browser-results.json`. The rerunnable browser function is `browser-route-audit.js`; it requires a same-origin T3 page and loaded axe source. Plans and decisions are stored alongside this report.

## Limits

Changes are local and have not been deployed. T3 screenshot capture repeatedly failed with PreviewAutomationExecutionError, so no final image-based visual verdict is claimed. DOM/computed-style, axe and interaction evidence does not replace a human visual review or screen-reader review. Automated checks also do not establish a conversion lift; that requires production funnel data after deployment.

## Latest-main integration for the PR

Merged main through `b3a39a4` in an isolated worktree, including legal/press routes and production analytics/paid attribution. The original workspace's staged app work was not used. The final PR diff contains no native app changes.

Expanded the coastal layout to privacy, terms and press without changing legal prose or downloadable press assets. Preserved FAQ schema and changed its check to compare rendered questions/answers with structured data. Shared canonical typography tokens now resolve the body-scoped local font, while section headings retain their native rounded face.

The merged production build and its complete main-branch check suite pass: 65 exported pages, 57 direct-download actions, 128 SwagUI Button slots, no static issues. All 65 routes pass a fresh T3 320px axe/layout run with no reported violations or detected overflow; all hero fonts resolve to the coastal serif. Additional desktop and enlarged-text checks on new legal/press routes passed layout checks. A press-caption contrast failure found during integration was corrected before the final 65-route run. Manual contrast checks over photos and video-caption review remain outside the automated result.

Current merged browser evidence is `merged-main-browser-results.json`; earlier 61-page evidence remains a historical snapshot. Screenshot capture limitations above still apply.
