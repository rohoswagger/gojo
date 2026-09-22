This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Analytics

The site records anonymous pageviews plus download and pricing-CTA clicks when `NEXT_PUBLIC_POSTHOG_KEY` is set at build time. A random temporary browser-session identifier in `sessionStorage` separates visits without using email, license data, device identifiers, cookies, or a stable identifier across sessions. Query strings and URL fragments are removed from analytics destinations.

For Stripe Payment Links, the same pseudonymous session value is attached as `client_reference_id`. Stripe returns it in a signed `checkout.session.completed` webhook so the Worker can send a privacy-limited `purchase_completed` event to PostHog. The event contains checkout mode, payment status, currency, amount, and attribution state; it does not forward customer email, payment details, Stripe customer IDs, license keys, or Checkout Session IDs.

Set `NEXT_PUBLIC_POSTHOG_KEY` in the production build environment before deploying. It is a public PostHog project token, not a server secret. Leave it unset for local builds that should not send browser analytics.

The Worker route `POST /api/stripe/webhook` requires two runtime secrets: `STRIPE_WEBHOOK_SECRET` for signature verification and `POSTHOG_API_KEY` for server-side capture. Configure Stripe to send `checkout.session.completed` and `checkout.session.async_payment_succeeded` to `https://trygojo.com/api/stripe/webhook`. Install both values with `wrangler secret put` through a protected prompt; never place them in source, `wrangler.jsonc`, command arguments, logs, or screenshots. The route fails closed when either binding is absent and returns an error when PostHog delivery fails so Stripe can retry.

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
