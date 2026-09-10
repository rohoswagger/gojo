# Gojo web — design

Two worlds share one chrome. Neither is a variant of the other; each is chosen
for what its readers came to do.

## The chrome (all routes)

A **floating bar**, not a full-bleed one: `.site-header` is a rounded rect
(16px) at the page measure, sticky with a small top gap, hairline border, no
shadow. It sits *on* the page ground, which is what lets a tinted surface read
as a surface rather than as a band under the chrome.

Three columns: brand left, nav centred, one filled CTA right. Nav links are
pills — the only place pills belong, being small controls — and the current
section takes the filled one, so wayfinding survives a screenshot. Under 40rem
the bar becomes two rows: identity and action together, nav beneath.

Elevation is declared **once**, as a hairline. A 1px border under a wide soft
shadow is the ghost card.

## World 1 — the site skin (`app/skin.css`)

White ground, hairline rules as the primary structural device, tight display
type, bordered 8px cards, no shadows. System type stacks throughout
(`ui-rounded` display, `ui-sans-serif` body, `ui-monospace` data). Ink is alpha
on white in four tiers; `--ink-4` is borders only, never words.

Routes: `/`, `/features/*`, `/alternatives/*`, `/downloads`. Unchanged.

## World 2 — blog paper (`app/blog-paper.css`)

Routes: `/blog`, `/blog/*`. Scoped entirely to `.blog-paper`, which **repaints
the shared tokens** — `--surface` tiers, rules, `--display`, `--body`, the ink
floor — so every existing rule in `skin.css` (article prose, tables, answer
boxes, FAQ, CTA) inherits the world without being restated. `/features/*` and
`/alternatives/*` never see the class.

**Ground.** Warm cream `#f8f6f0`; tiles `#efebe0`; rules `#e2dccd`. The ink
tiers stay alpha-on-black: composited on a warm ground they land on warm grays
for free, which is what tinting secondary text from the hue asks for. `--ink-3`
is deepened to `0.6` because `0.55` on this cream sits at 4.5:1 exactly. Every
painted text/ground pair measures ≥5.48:1.

**Type.** One tight grotesque for everything — **Inter Tight**, self-hosted via
`next/font` in `app/layout.tsx` — with **Instrument Serif** italic reserved for
the single emphasised word in a poster, and nowhere else. Display tops out at
5.5rem; tracking bottoms out at −0.04em. Mono is `ui-monospace` and appears
only on data: dates, counts, reading times, all `tabular-nums`. Words that are
labels are tracked caps instead.

**Blue.** Gojo's `--gojo-accent` `#4a46cf`, carried over from the site skin. It
marks exactly three things: the poster rule, the topic label, the in-prose link.

**The poster.** The signature. Every post carries an authored 2–3 line hook in
`content/blog/_hub.json` — line breaks are the composition, not wrapping — set
on a filled tile with a short blue rule beneath. Type sizes in **container
query units** (`cqi`), so the hook is optically identical in a 3-up grid and a
1-up mobile column. On a card the tile is 8:5; as an article masthead it becomes
a 32:7 band.

**Cards have no container.** The tile is the only filled surface; title, summary
and meta sit on the page ground. One fewer box, one fewer border.

**Radii.** Cards and tiles 14–18px. Pills for small controls only.

**Motion.** One authored moment: posters resolve into place — translate, fade,
and **blur** out of 7px — on an exponential ease-out, staggered 34ms and capped
at nine items so nothing waits longer than ~300ms. It replays on filter change
because the grid is keyed on the active topic. Hover grows the blue rule via
`transform: scaleX`, never `width`. All of it off under
`prefers-reduced-motion`.

**Browser surfaces.** Selection, caret, scrollbar and focus ring are themed from
the paper palette inside `.blog-paper`. The parts nobody draws still carry the
design.

## Bans

- No eyebrow or kicker above a heading. The heading carries its own weight.
- No gradient text; emphasis is weight, size, or the serif italic.
- No system face as an own-world display voice — hence the self-hosted pair.
- No monospace as a costume for "technical". Numbers only.
- No nested cards, no shadow under a border, no `border-left` accents.
