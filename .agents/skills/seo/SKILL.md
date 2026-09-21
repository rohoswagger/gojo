---
name: seo
description: Run Gojo's evidence-led organic growth loop.
version: 1.0.0
author: Roshan Desai, Hermes Agent
license: GPL-3.0
platforms: [linux, macos]
metadata:
  hermes:
    tags: [seo, aeo, geo, content, technical-seo, distribution]
    related_skills: []
---

# Gojo SEO Operator

Own Gojo's organic acquisition stack: classic search, answer engines, technical health, editorial and programmatic content, claim accuracy, internal links, backlinks, directory distribution, and conversion from organic visits. Each heartbeat measures first, ranks all eligible actions on one scale, executes the best one, verifies it, and records the result.

This is an operator, not a content quota. Correcting or distributing something already live often beats creating another page. A measured no-op is valid when no action clears the bar.

## When to Use

- Every Gojo growth heartbeat.
- SEO, AEO, GEO, LLM visibility, Search Console, indexing, sitemap, schema, content, internal links, backlinks, directories, or organic CRO.
- Forced work on a named defect, topic, page, free tool, or distribution target.

Do not use this skill to merge a PR, spend money, change pricing, alter secrets, make legal claims, fabricate evidence, send bulk outreach, or deploy unmerged code.

## Modes

| Mode | Behavior |
|---|---|
| `hourly` | Measure, rank all eligible actions, execute one, verify, register. Default for every hourly heartbeat. |
| `measure` | Measure and register only. Select and execute nothing. |
| `fix <target>` | Force repair/refresh for a named page, claim, or defect. |
| `write [topic]` | Force one editorial piece after validating demand and overlap. |
| `sprint` | Force the next programmatic roadmap phase. |
| `tool [idea]` | Force a free-tool build after validating relevance and conversion path. |
| `aeo [snapshot|audit|plan|fix]` | Force answer-engine work. |
| `tech` | Repair the worst verified technical violation. |
| `census` | Review the whole inventory and execute the best prune, merge, or refresh. Never create. |
| `offpage` | Execute the next legitimate directory or outreach action, or produce a ready brief when submission is blocked. |
| `distribute [url]` | Distribute the named or newest undistributed asset. |
| `needs-you` | Print only decisions requiring Roshan. |
| `setup` | Print connected data sources and missing connections in value order. |

Forced modes still perform a cheap measurement and register the run. They skip only cross-lane selection.

## State Contract

`.seo/` is the only operator-state directory and must remain gitignored. Never stage it.

Expected files:

- `.seo/config.json`: domain, Search Console property, analytics project, conversion targets, cadence.
- `.seo/truth.md`: verified product, pricing, privacy, compatibility, and release claims with sources.
- `.seo/coverage.md`: topic clusters, intent owners, cannibalization notes, and rejected topics.
- `.seo/content-ledger.md`: every indexable page, target query, funnel role, status, and last action.
- `.seo/link-inventory.md`: important internal links, orphans, broken links, redirects, and off-page placements.
- `.seo/candidates.json`: scored candidate actions from the current run.
- `.seo/runs/YYYY-MM-DD-HHMM.md`: one append-only run record per heartbeat.
- `.seo/needs-you.md`: decisions only Roshan can make.

Initialize missing files from `assets/` using `scripts/init_state.py`. Never overwrite existing state. Read legacy `marketing/heartbeat/` records when useful, but write new state only to `.seo/`.

## Non-Negotiable Gates

1. **Current evidence:** measure before choosing. Use Google Search Console, PostHog, DataForSEO, the live site, repository state, and recent run records when available.
2. **One winner:** execute the highest-scoring eligible action only. Finish it before starting another.
3. **Live defects first:** broken indexing, inaccurate claims, broken internal links, redirect chains, severe speed regressions, and low-CTR winning pages compete against new content and usually outrank it.
4. **Intent ownership:** every page and candidate has one primary query/intent owner and one conversion destination. Reject cannibalizing or off-topic pages.
5. **Truth:** product, pricing, privacy, download, compatibility, and competitor claims must resolve to the truth ledger or a current authoritative source.
6. **Review path:** code and content changes ship only through a focused PR. Never merge. Every web UI PR follows `.agents/skills/pr-web-screenshots/SKILL.md` when present.
7. **External proof:** a submission, publication, deployment, or listing is complete only after reading back the exact public target. CAPTCHA-blocked work is prepared, not submitted.
8. **No sensitive analytics:** never collect dictated text, audio, clipboard contents, filenames, window titles, license keys, machine IDs, email addresses, or raw URLs with query strings/fragments.
9. **No invented work:** if no candidate clears the action bar, register the measurements and stop.

## Hourly Procedure

### 0. Establish current state

1. Confirm the repository branch, open PRs, recently merged work, and ignored-state status.
2. Read `.seo/config.json`, `.seo/truth.md`, the latest three run records, and relevant ledgers.
3. If state is absent, run `python3 .agents/skills/seo/scripts/init_state.py` through `terminal` and fill only facts supported by the repository or connected sources.

Complete when duplicate/open-PR conflicts and the last action are known.

### 1. Measure all four vitals

Read `references/measure.md` and collect:

- **Speed:** TTFB and HTML weight for the homepage and current winning/changed pages. Use Lighthouse weekly, not every heartbeat.
- **Relevance:** page-to-query alignment, wrong-query visibility, realistic keyword demand, and competitor coverage.
- **Google CTR:** per-page/query impressions, clicks, position, CTR, and CTR gap using identical complete-date filters.
- **Link health:** broken or redirecting internal links, orphans, click depth, and legitimate referring placements.

Also inspect the organic conversion path in PostHog when events exist. Treat missing instrumentation as a candidate, not permission to invent conclusions.

Complete when the run has a timestamped evidence window and comparable baseline.

### 2. Generate and score candidates

Create candidates across every eligible lane:

- `correct`: inaccurate live claim or product mismatch.
- `repair`: technical/indexing/speed/link defect.
- `refresh`: title/snippet/content/intent/internal-link improvement.
- `consolidate`: merge cannibalizing or redundant pages.
- `prune`: remove or redirect low-value pages.
- `distribute`: internal links, directories, editorial/community distribution.
- `offpage`: legitimate outreach or backlink repair.
- `editorial`: one evidence-backed article.
- `programmatic`: one roadmap phase, never an unbounded page factory.
- `tool`: a useful free tool with a clear query and conversion path.
- `aeo`: answer ownership, citation readiness, structured facts, or platform visibility.
- `measurement`: instrumentation needed to resolve a high-value decision.

Score every candidate using `references/select.md` and `scripts/score.py`. Reject candidates that violate truth, relevance, review, cost, or conflict gates.

Complete when `.seo/candidates.json` contains the ranked list, rejection reasons, and one winner or an explicit no-op.

### 3. Execute one lane

Read the matching lane section in `references/lanes.md` and execute the smallest complete version of the winner.

For repository changes:

1. Fetch `origin/main`.
2. Create an ignored `.worktrees/` worktree and focused branch from current `origin/main`.
3. Add a regression contract before or with the change.
4. Run focused checks, lint, production build, link/claim checks, and `git diff --check`.
5. Capture and inspect branch-built desktop/mobile screenshots for web UI changes.
6. Independently review substantial or risky changes.
7. Push and open a PR. Do not merge.

For external actions, use the official submission/contact route, remain factual and low-volume, and verify the public result.

Complete when the chosen action has a verifiable artifact: PR URL, live URL, confirmed submission receipt, corrected state, or documented blocker.

### 4. Verify

Verification is non-waivable:

- Re-read every changed claim against its source.
- Test changed routes and links.
- Confirm expected rendered metadata/schema with a browser or built output, not stripped text extraction.
- Confirm the action did not create duplicate intent, indexable low-value pages, analytics leakage, or open-PR conflicts.
- For deployments of already merged Gojo web PRs, use a fresh worktree at the merged commit, run frozen install/build/dry-run, deploy the existing Worker, and verify the exact production routes. Report the Cloudflare version. Never deploy an unmerged PR.

### 5. Register and report

Read `references/register.md`. Write the run record even when no action is taken. Update ledgers only for facts changed by the run.

The final heartbeat message contains only:

- what was completed;
- the strongest evidence;
- PR, live, or external URLs;
- verification result;
- one real approval gate, if any.

Do not replay the process or print a backlog.

## Cadence

- Every heartbeat: repository/PR state, GSC complete-date delta, candidate dedupe, live-route health for the winner, and one selected action.
- Daily: broader keyword/page changes, content/link inventory changes, and organic funnel state.
- Weekly: Lighthouse/PageSpeed on top landing pages, competitor visibility, schema/render audit, and distribution follow-up.
- Monthly: `census` mode, backlink/spam review, content decay, topic/intent ownership, and portfolio trend.

Do not run paid or slow panels more frequently than their data changes.

## Pitfalls

- A new article is not automatically progress. Existing CTR, accuracy, link, or indexing defects often have higher expected value.
- GSC partial days distort comparisons. Use complete dates and preserve filters.
- Similar keywords do not justify separate pages when intent and SERPs overlap.
- Search volume is not Gojo relevance. Reject traffic that cannot credibly convert.
- Static fetchers may miss JavaScript-injected schema. Inspect rendered DOM or built HTML.
- A browser click is not a download, checkout is not a purchase, and UI license entry is not payment verification.
- Repeated outreach without a reply is spam. Record contact history and stop after the defined follow-up.
- Do not modify `marketing/heartbeat/` or `.seo/` into Git history.

## Verification Checklist

- [ ] All four vitals measured or explicitly marked unavailable.
- [ ] Every candidate scored on the same rubric.
- [ ] One eligible winner executed, or a grounded no-op recorded.
- [ ] Claims and links verified against authoritative sources.
- [ ] Relevant tests/build/checks passed.
- [ ] External writes read back from the exact target.
- [ ] `.seo/` and `marketing/heartbeat/` remain untracked.
- [ ] Run record and affected ledgers updated.
- [ ] Final report states completed work and the true gate only.
