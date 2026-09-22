import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const source = (path) => readFileSync(resolve(path), "utf8")
const layout = source("app/layout.tsx")
const analytics = source("components/funnel-analytics.tsx")
const home = source("app/page.tsx")
const worker = source("worker.mjs")
const privacy = source("app/privacy/page.tsx")
const readme = source("README.md")

if (!layout.includes("<FunnelAnalytics />")) {
  throw new Error("root layout must mount FunnelAnalytics so every marketing page records pageviews")
}

for (const required of [
  '"$pageview"',
  "data-funnel-event",
  "NEXT_PUBLIC_POSTHOG_KEY",
  "navigator.sendBeacon",
  "usePathname",
  "urlWithoutQueryOrHash",
  "crypto.randomUUID",
  "sessionStorage",
  "$session_id:",
  "$process_person_profile:",
  '"client_reference_id"',
  '"auxclick"',
  "event.button !== 1",
  ".catch(() => {})",
]) {
  if (!analytics.includes(required)) {
    throw new Error(`funnel analytics is missing ${required}`)
  }
}

if (analytics.includes('distinct_id: "anonymous"')) {
  throw new Error("funnel analytics must not collapse every visitor into one shared identity")
}

for (const required of [
  'data-funnel-event="download_cta_clicked"',
  'data-funnel-event="pricing_cta_clicked"',
  'data-funnel-plan=',
]) {
  if (!home.includes(required)) {
    throw new Error(`home page is missing ${required}`)
  }
}

for (const required of [
  '"/api/stripe/webhook"',
  "STRIPE_WEBHOOK_SECRET",
  "POSTHOG_API_KEY",
  '"purchase_completed"',
  "$insert_id:",
  "verifyStripeSignature",
]) {
  if (!worker.includes(required)) {
    throw new Error(`purchase webhook is missing ${required}`)
  }
}

for (const required of [
  "temporary browser-session identifier",
  "client_reference_id",
  "purchase_completed",
]) {
  if (!privacy.includes(required) && !readme.includes(required)) {
    throw new Error(`analytics documentation is missing ${required}`)
  }
}

if (!readme.includes("NEXT_PUBLIC_POSTHOG_KEY")) {
  throw new Error("README must document the PostHog build variable")
}

console.log("funnel analytics source contract passed")
