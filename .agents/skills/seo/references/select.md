# Candidate Selection

All lanes use one rubric. Score only candidates supported by current evidence.

## Required candidate fields

```json
{
  "id": "stable-short-id",
  "lane": "repair",
  "target": "https://trygojo.com/example/",
  "problem": "Observed problem",
  "evidence": ["Source and measurement"],
  "evidence_age_days": 0,
  "intent_owner": "Primary query or reader job",
  "conversion_destination": "Download, pricing, or another owned next step",
  "metrics": {
    "business_impact": 0,
    "evidence_strength": 0,
    "relevance": 0,
    "ctr_potential": 0,
    "link_health": 0,
    "speed": 0,
    "effort": 0,
    "risk": 0,
    "conflict": 0
  },
  "eligible": true,
  "rejection_reason": null
}
```

Each metric is an integer from 0 through 5.

## Formula

```text
score =
  3 × business_impact +
  2 × evidence_strength +
  2 × relevance +
  2 × ctr_potential +
  2 × link_health +
  1 × speed -
  1 × effort -
  2 × risk -
  2 × conflict
```

Use `python3 .agents/skills/seo/scripts/score.py .seo/candidates.json --write` to validate, rank, select the winner, and persist the ranked state. The script reads `action_bar` from the adjacent `.seo/config.json`; `--action-bar N` is an explicit one-run override. The output is deterministic.

## Scoring anchors

- **Business impact:** 0 no plausible qualified impact; 3 moves discovery or a funnel step; 5 fixes a proven high-volume or revenue path.
- **Evidence strength:** 0 intuition; 3 one current first-party source; 5 multiple agreeing first-party/live sources.
- **Relevance:** 0 off-topic; 3 adjacent problem; 5 exact Gojo capability and buyer intent.
- **CTR potential:** 0 no impression/snippet effect; 3 measurable low CTR; 5 high impressions with a large position-adjusted gap.
- **Link health:** 0 irrelevant; 3 repairs or adds useful path; 5 fixes a broken high-value path or strong orphan.
- **Speed:** 0 no effect; 3 probable meaningful improvement; 5 measured severe regression on a winning page.
- **Effort:** 0 under 30 minutes; 3 one focused PR/day; 5 multi-day or cross-system.
- **Risk:** 0 reversible/internal; 3 claim/indexing/external uncertainty; 5 legal, money, secrets, irreversible, or brand-dangerous.
- **Conflict:** 0 isolated; 3 overlaps active PR/work; 5 duplicates or invalidates it.

## Eligibility gates

Mark ineligible before ranking when the action:

- needs spending, pricing, legal approval, secrets, merging, or irreversible commitment;
- conflicts with an open PR or completed recent run;
- relies on an unverified product/competitor claim;
- creates doorway, duplicate-intent, or irrelevant traffic pages;
- cannot be verified this run;
- repeats unsolicited outreach beyond the contact policy.

## Selection

- Default action bar: score at least 12 and `eligible=true`.
- Ties resolve by: correct/repair first, then stronger first-party evidence, then lower effort, then older unresolved evidence.
- Forced modes choose only within that lane but still apply eligibility gates.
- If no candidate clears the resolved action bar, record a no-op with the top rejected/low-score candidate and reason.
