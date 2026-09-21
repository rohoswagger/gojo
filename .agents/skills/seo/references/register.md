# Register and Report

## Run record

Create `.seo/runs/YYYY-MM-DD-HHMM.md` for every invocation, including measure-only and no-op runs.

```markdown
# SEO run — <UTC timestamp>

Mode: hourly
Evidence window: <complete dates, timezone, filters>

## Vitals
- Speed: ...
- Relevance: ...
- CTR: ...
- Links: ...

## Candidate ranking
1. <score> — <lane> — <target> — <one-line evidence>
2. ...

Winner: <id or none>
Why: <why this beat all other lanes>

## Executed
- <completed action>

## Verification
- <command/source/readback and result>

## Artifacts
- PR/live/external URL: ...
- Commit/deployment version: ...

## Outcome checkpoint
- Baseline: ...
- Earliest useful recheck: ...

## Rejected or deferred
- <candidate>: <grounded reason>

## Human gate
- None | <one decision Roshan must make>
```

## Ledger updates

Update only changed facts:

- content ledger after create/refresh/consolidate/prune;
- link inventory after internal/off-page work;
- truth ledger after authoritative product/pricing/release changes;
- coverage map after intent-owner changes;
- needs-you queue after a real human-only decision appears or is resolved.

Never rewrite historical run records to make later outcomes look better.

## Outcome follow-up

At or after the earliest useful recheck, compare the identical saved filters and append an outcome note to a new run. Distinguish observation from attribution. Do not declare SEO success from indexing alone or conversion success from a CTA click.

## Final response

Keep it short and standalone:

1. completed action;
2. strongest observed evidence;
3. artifact URL;
4. verification;
5. true approval gate, if any.

If no action cleared the bar: `Measured <window>. Nothing new cleared the action bar; <short reason>.` Do not invent progress.
