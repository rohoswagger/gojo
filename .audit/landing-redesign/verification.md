# Verification and launch notes

Production build and marketing link checks pass. Full lint has zero errors and the two existing next/no-img-element warnings in night-shift-comparison.tsx. The analytics contract script passes with mocked transport.

In the T3 in-app browser, verified real screenshot selection, visible Multi-Mac pricing, Home-key navigation back to Personal, FAQ content, no failed loaded images, all three direct trial CTAs, and four preserved payment links. Final rendered stage center was 444.75 CSS px against viewport center 444.5 px. Trial CTA bottom was 429.85 px in the 1095 px viewport. T3 same-origin iframe layout checks at 320, 390, 768 and 1440 CSS px found no horizontal overflow, and the trial CTA remained above the fold at 900 px height. Seven screenshot elements render across six unique product captures.

The T3 screenshot operation repeatedly failed, and resize disconnected the host. Do not describe blank generated screenshots as final visual proof. Removed two blank captures. The valid mobile-final.png records the revised composition before the centering-only correction. Earlier desktop.png and mobile.png are first-draft history.

PostHog baseline is aggregate distinct IDs, not proven independent people. SessionStorage identity is preserved from the live contract, so report session-scoped intent conversion. The saved funnel has 45 IDs, 2 pricing clicks and zero attributed completions; the independent purchase insight has one unattributed $9.99 sale. Homepage has 30 IDs. No download baseline exists.

Primary after-launch metric is ordered homepage $pageview to download_cta_clicked within the same anonymous session, filtered homepage_version=workbench_v1. Segment by placement, viewport_class, os_family and referring_domain. Pricing exposure and pricing clicks are secondary. Observe counts before claiming uplift. Do not compare these short-lived IDs as stable returning-user cohorts.

Launch remains separate from this local redesign. Supply NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN or NEXT_PUBLIC_POSTHOG_KEY at build time and verify production ingestion plus Stripe reference joining after a separately authorized deployment. The local browser intentionally sends no captures. Do not re-add deployed analytics separately or events will duplicate. Current checkout source predates the live downloads release metadata; reconcile that release before deployment. No deploy, purchase, analytics setting change or native app edit was performed.
