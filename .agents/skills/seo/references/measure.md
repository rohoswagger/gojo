# Measurement

Use identical filters and complete dates so runs are comparable. Record source, property/project, timezone, date range, dimensions, filters, and retrieval time for every panel.

## Cheap panel, every heartbeat

1. **Repository and delivery state**
   - Fetch remotes and list open/merged PRs.
   - Detect pending deployments and overlapping branches.
   - Confirm `.seo/` and `marketing/heartbeat/` are ignored and untracked.
2. **Live health**
   - Request the homepage, sitemap, robots file, and the page relevant to the prior/current winner.
   - Record status, redirect chain, canonical destination, TTFB, and HTML bytes.
3. **Search Console**
   - Use the latest complete date only.
   - Compare the same page/query/country/device/search-type filters against the saved prior pull.
   - Record clicks, impressions, CTR, position, and deltas.
   - Classify: `striking-distance`, `low-ctr`, `wrong-query`, `decay`, `new`, or `stable`.
4. **Links**
   - Check changed/priority pages for broken links, internal redirects, inbound contextual links, and obvious orphans.
5. **Decision blockers**
   - Check PostHog only for events that are actually implemented.
   - Record missing event coverage instead of inferring conversions.

## Daily panel

- GSC top queries and pages over 7-, 28-, and prior comparable windows.
- DataForSEO keyword and SERP evidence for the highest-value candidates.
- Index/sitemap inventory drift.
- Organic landing-page to download/pricing event flow in PostHog.
- Content and distribution ledger changes.

## Weekly panel

- Lighthouse or PageSpeed for homepage and highest-impression landing pages.
- Rendered metadata, canonical, robots, JSON-LD, and mobile overflow audit.
- Competitor page/keyword changes for NotchNook, Alcove, Droppy, and newly proven SERP competitors.
- Off-page placements and unanswered outreach eligible for one follow-up.

## Monthly panel

- Whole inventory census: intent ownership, thin pages, duplication, decay, no-impression pages, orphan status, and conversion destination.
- Backlink/referring-domain trend and spam review.
- Portfolio totals: indexable URLs, clicks, impressions, weighted CTR gap, non-brand share, organic conversion signals, healthy/broken links, and pages by action state.

## Four-vital block

Every run record includes:

```text
Speed: homepage TTFB __ ms; winner TTFB __ ms; HTML __ KB; trend __
Relevance: aligned __; wrong-query __; cannibalization __; trend __
CTR: clicks __; impressions __; CTR __; weighted gap __; trend __
Links: broken __; redirecting __; orphans __; new verified placements __; trend __
```

Use `unavailable: <reason>` only after checking the source. Do not substitute estimates for unavailable observed values.
