# Gojo website

The marketing site uses Next.js with static export. Article data lives in
`content/blog`. Feature and alternative pages use the HTML generators in `lib`.
Shared coastal styles live in `app/marketing-heroes.css` over the base `app/skin.css`. React actions use the local SwagUI
`Button` in `components/ui/button.tsx`.

## Run locally

From `web`, install the locked dependencies and start the development server.

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Open `http://localhost:3000`. Run the source checks before a build.

```sh
pnpm lint
pnpm exec tsc --noEmit
```

`pnpm build` writes the static site to `out` and runs the marketing link and
accessibility checks, followed by the full route crawl. `pnpm verify:marketing`,
`pnpm verify:accessibility` and `pnpm audit:site` check an existing export.
The route crawl validates local assets, fragments, landmarks, canonicals and download tracking.

## Update release details

`lib/release.mjs` pairs the download page's version, immutable artifact URL, byte
size and SHA-256. The homepage also uses this release record for its version.
Keep the versioned URL and checksum together. The mutable `Gojo.dmg` alias can
change after a release.

Before updating the record, compare `../appcast.xml` with the release tag and
download the versioned artifact. Read the actual byte count and SHA-256.

```sh
curl --fail --location --output /tmp/Gojo-1.7.1.dmg 'https://downloads.trygojo.com/Gojo-1.7.1.dmg'
wc -c < /tmp/Gojo-1.7.1.dmg
shasum -a 256 /tmp/Gojo-1.7.1.dmg
```

The published 1.6.0 artifact was downloaded for the cleanup audit and measured
again locally on 2026-10-19. Its 17,399,815 bytes match the published appcast
enclosure. Its SHA-256 is
`65f3291ee7f613269ea550cf24dd5ab69f170f85c529771b62be3c3038a9da8a`.
The press verifier imports this record and independently checks the native
project's marketing version.

## Preserve page behavior

Keep each route's heading and body in one focusable `main#main-content`, with the
header outside. Preserve blog canonicals, article JSON-LD, fragment IDs and
article content. Use existing screenshots at their native aspect ratios.

Direct DMG links carry `data-funnel-event="download_cta_clicked"` and a fixed
`data-funnel-placement` value such as `downloads` or `blog_article`. Keep license
links and purchase attribution intact.

## Analytics

The site records anonymous pageviews plus download and pricing-CTA clicks when `NEXT_PUBLIC_POSTHOG_KEY` is set at build time. A random temporary browser-session identifier in `sessionStorage` separates visits without using email, license data, device identifiers, cookies, or a stable identifier across sessions. Query strings and URL fragments are removed from analytics destinations.

For Stripe Payment Links, the same pseudonymous session value is attached as `client_reference_id`. Stripe returns it in a signed `checkout.session.completed` webhook so the Worker can send a privacy-limited `purchase_completed` event to PostHog. Only paid live-mode checkouts from the four Gojo Payment Links are captured. The event contains the selected plan, checkout mode, payment status, currency, amount, and attribution state; it does not forward customer email, payment details, Stripe customer IDs, license keys, or Checkout Session IDs.

Set `NEXT_PUBLIC_POSTHOG_KEY` or the existing `NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN` in the production build environment before deploying. `NEXT_PUBLIC_POSTHOG_HOST` selects the capture host and defaults to `https://us.i.posthog.com`. It is a public PostHog project token, not a server secret. Leave it unset for local builds that should not send browser analytics.

The Worker route `POST /api/stripe/webhook` requires two runtime secrets: `STRIPE_WEBHOOK_SECRET` for signature verification and `POSTHOG_API_KEY` for server-side capture. Configure Stripe to send `checkout.session.completed` and `checkout.session.async_payment_succeeded` to `https://trygojo.com/api/stripe/webhook`. Install both values with `wrangler secret put` through a protected prompt; never place them in source, `wrangler.jsonc`, command arguments, logs, or screenshots. The route fails closed when either binding is absent and returns an error when PostHog delivery fails so Stripe can retry. Each Stripe Event uses a deterministic UUID, its original timestamp, and the same distinct ID so PostHog can deduplicate replayed deliveries. This deduplicates retries of an Event ID; separate Stripe Event IDs are separate records. Subscription renewals and refunds are outside this acquisition event. Keep the Gojo Payment Link allowlist in `worker.mjs` aligned with the four website plans.

