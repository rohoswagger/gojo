import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const source = (path) => readFileSync(resolve(path), "utf8")
const layout = source("app/layout.tsx")
const analytics = source("components/funnel-analytics.tsx")
const home = source("app/page.tsx")
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
  '"auxclick"',
  "event.button !== 1",
  ".catch(() => {})",
]) {
  if (!analytics.includes(required)) {
    throw new Error(`funnel analytics is missing ${required}`)
  }
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

if (!readme.includes("NEXT_PUBLIC_POSTHOG_KEY")) {
  throw new Error("README must document the PostHog build variable")
}

console.log("funnel analytics source contract passed")
