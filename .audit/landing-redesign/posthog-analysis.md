# Gojo PostHog conversion investigation

Observed on 2026-10-16 through authenticated PostHog project 613832. Read-only UI inspection and unsaved SELECT queries. No dashboard, insight, event, person, or project settings were saved or changed.

## Findings

1. The saved website funnel shows 45 unique persons visiting any trygojo.com page, 2 continuing to `pricing_cta_clicked`, and 0 continuing to an attributed `purchase_completed`. Its displayed pricing-click rate is 4.44%, with 43 people dropping before the click. Confidence is high in the displayed result, low in any causal explanation or predicted redesign uplift.
2. The funnel's time range is 2026-09-16 00:00 through 2026-10-16 23:59 UTC. It counts unique users, requires sequential steps, and uses a 14-day conversion window. Step one filters `$pageview` with Current URL containing `https://trygojo.com`. Step three requires `attributed = true`. There is no breakdown. The saved description says historical purchases lacking a site reference are excluded and other-device or browser-session purchases may remain unattributed.
3. The purchase insight shows one `personal_lifetime` initial purchase for $9.99 gross and zero attributed purchases in a rolling 30-day window. Its SQL selects `purchase_completed` with `source = stripe_webhook`, groups by event UUID before summing, and excludes renewals/refunds by its documented event scope. This purchase occurred 2026-09-21 15:26:24 UTC. It predates both observed pricing clicks. Do not present zero attributed funnel completions as no sales.
4. The homepage has 57 pageview events from 30 distinct IDs. Both pricing clicks occurred on `/`. The existing saved funnel includes blog and feature-page visitors, so its 4.44% is not a homepage-only conversion rate. Raw 2/30 is 6.67%, but an ordered homepage-specific funnel should be used for an actual landing-page conversion baseline.
5. The two clicks split evenly between `personal_lifetime` on 2026-10-12 23:02:36 UTC and `personal_monthly` on 2026-10-14 10:49:22 UTC. This cannot establish a preference for either plan. The saved funnel reports median visit-to-click time of 8m58s across only two people. That is not an estimate of ordinary visitor attention or evidence that the page takes nine minutes to understand.
6. The complete 30-day event inventory contains only `$pageview`, `pricing_cta_clicked`, `purchase_completed`, and `setup_verification`. Live query totals were 105 pageviews from 45 distinct IDs, two pricing clicks from two IDs, one purchase from one ID, and one setup verification. There are no recorded download clicks, demo interactions, pricing-section views, feature selections, or checkout starts in this inventory. This is a measurement gap, not proof those actions never happened.
7. All 105 pageviews have missing `$device_type`, `$os`, `$browser`, `$referring_domain`, and `utm_source`. Enumerating property keys confirmed those fields are absent. Current data cannot justify mobile-versus-desktop or channel-specific conversion decisions. Only 52 of 105 pageviews carry `$session_id`. The two pricing events do carry it. Session instrumentation changed or differs across the observed period, but the cause requires source inspection.
8. The starter dashboard is generic. Cached insights computed roughly five minutes earlier show 44 active unique people in 30 days, 43 sessions and 51 pageviews in seven days. Its canned pageview-to-autocapture funnel reports 43 people and zero autocapture interactions. The explicit custom click events establish that zero autocapture is not evidence of zero interactions. Use explicit events instead.
9. Activity is recent and sparse. Cached daily active counts are 1 on Oct12, 14 on Oct13, 9 on Oct14, 14 on Oct15, and 5 on Oct16. The latest fresh pageview was 2026-10-16 21:13:56 UTC. Retention's newest weekly cohort has 43 people and no mature week-one observation. Do not infer poor retention from its blank follow-up cell or aggregate zero.

## Redesign implications

- Make the next action and product behavior clear immediately. Only two recorded purchase-intent clicks exist, so the first measurable improvement should be qualified interest, followed by completed paid checkouts.
- Show a real Gojo workflow near the hero and keep one primary action consistent. These are design hypotheses based on product clarity, not statistically established causes of the observed drop-off.
- Keep the plan choice legible. Current data cannot prove lifetime should dominate monthly. Avoid inventing urgency, testimonials, social proof, savings, or conversion uplift.
- Instrument download and primary CTA actions separately from paid-plan clicks. Record placement, plan, page path, and landing version. Measure pricing exposure before concluding that price caused abandonment.
- Maintain purchase-event deduplication and temporary site-reference attribution through checkout. Report attributed conversion and total purchases separately.
- Add privacy-conscious device class and acquisition metadata if segmentation is needed. Avoid collecting full query strings or personal identifiers. Audit internal/test traffic filters before comparing releases.
- Evaluate the redesign against a homepage-specific ordered funnel and a version field. With this traffic, report counts and qualitative behavior before declaring an A/B winner.

## Source links

- [Website funnel](https://us.posthog.com/project/613832/insights/4yXfjkkf).
- [Purchases by plan](https://us.posthog.com/project/613832/insights/G8EdwuQJ).
- [Starter dashboard](https://us.posthog.com/project/613832/dashboard/2105637).
- [Cached active users](https://us.posthog.com/project/613832/insights/L3nke2GL).
- [Cached sessions](https://us.posthog.com/project/613832/insights/WhQQryJR).
- [Cached pageviews](https://us.posthog.com/project/613832/insights/GkHdBpRP).
- [Daily activity](https://us.posthog.com/project/613832/insights/J7bIoH9Q).
- [Weekly activity](https://us.posthog.com/project/613832/insights/ejkYshBX).
- [Retention](https://us.posthog.com/project/613832/insights/kmIiFTGp).
- [Top referrers](https://us.posthog.com/project/613832/insights/IJo3kZgU).
- [Generic autocapture funnel](https://us.posthog.com/project/613832/insights/FuCc64BI).

## Reproducible read-only SQL

Run as unsaved SQL insights in this project. Counts can increase with new traffic. These queries return aggregate data and property names, not individual identities or raw properties.

```sql
SELECT event, count() AS events, uniqExact(distinct_id) AS people,
       min(timestamp) AS first_seen, max(timestamp) AS last_seen
FROM events
WHERE timestamp >= now() - INTERVAL 30 DAY
GROUP BY event
ORDER BY events DESC
LIMIT 20
```

```sql
SELECT properties.$device_type AS device, properties.$os AS os,
       properties.$browser AS browser,
       properties.$referring_domain AS referring_domain,
       properties.utm_source AS utm_source,
       count() AS pageviews, uniqExact(distinct_id) AS visitors
FROM events
WHERE event = '$pageview' AND timestamp >= now() - INTERVAL 30 DAY
GROUP BY device, os, browser, referring_domain, utm_source
ORDER BY pageviews DESC
LIMIT 30
```

```sql
SELECT event, arrayJoin(JSONExtractKeys(properties)) AS property_name,
       count() AS events_with_property
FROM events
WHERE timestamp >= now() - INTERVAL 30 DAY
GROUP BY event, property_name
ORDER BY event, property_name
LIMIT 100
```

```sql
SELECT event, properties.page_path AS page_path, properties.plan AS plan,
       count() AS events, uniqExact(distinct_id) AS visitors,
       countIf(isNotNull(properties.$session_id)) AS with_session_id,
       toString(min(timestamp)) AS first_seen_utc,
       toString(max(timestamp)) AS last_seen_utc
FROM events
WHERE timestamp >= now() - INTERVAL 30 DAY
GROUP BY event, page_path, plan
ORDER BY events DESC
LIMIT 30
```

The Explain the Number principle changed the interpretation. Counts, attribution rules, time ranges, missing properties, and cohort maturity are reported together. The data supports a baseline and instrumentation priorities. It does not support a claimed redesign uplift.
