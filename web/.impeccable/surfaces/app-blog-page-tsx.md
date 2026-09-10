---
version: 1
slug: "app-blog-page-tsx"
primary_target: "app/blog/page.tsx"
related_targets: ["app/blog/[slug]/page.tsx","app/blog-paper.css"]
---

# /blog — surface brief

**Mode: Read.** The visitor came to understand something about their Mac. The
archive's job is to make 40 posts scannable in one pass and make the reading
experience worth staying in.

**Direction.** Pinned by a reference the user supplied: cream editorial paper,
one tight grotesque at display scale, a typographic poster per post in place of
stock cover imagery, pill topic filters, mono data. Gojo's own blue and logo
carry over; the reference's palette does not.

**Composition.** Floating chrome → oversized headline (2 lines, 18ch) → lede →
topic chips with counts → mono count line → 3-up poster grid. No pagination:
40 records filter client-side, which is faster than a route per topic on a
static export.

**Taxonomy.** Six topics — Notch (15), Dictation (11), Privacy (5), Windows (4),
Clipboard (3), File shelf (2) — replacing the previous format kickers
(Comparison / Roundup / Guide), which had four singleton buckets and told a
reader nothing about subject. Stored per post as `topic` in
`content/blog/_hub.json`.

**Poster copy.** 40 authored hooks, each derived from that post's own "Short
answer" thesis or summary — no invented claims, and every number in a hook
(six places, eight apps, four answers) is countable in the post it fronts. One
`*word*` per hook marks the serif italic run.

**Article pages** inherit the same world and reuse the poster as a masthead
band, so clicking a card does not change worlds. Hero copy and prose share one
left edge (both at 400px on a 1440 viewport); the masthead and the
"Continue reading" row are page-wide, giving the page two deliberate tiers.

**Per-card honesty.** Reading time comes from each post's own `hero.meta`. Posts
whose sources were verified against primary pages say "Sources checked"; the
others stay silent rather than all claiming it.
