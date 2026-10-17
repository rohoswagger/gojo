import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { parse } from 'node-html-parser';
import { resolve } from 'node:path';
import vm from 'node:vm';
import ts from 'typescript';

const source = readFileSync(new URL('../components/funnel-analytics.tsx', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
function mount({ hostname = 'trygojo.com', token = 'test-token', beacon = true, blockedStorage = false, observerAvailable = true, primaryToken, storedSession, beaconThrows = false, host } = {}) {
  const events = [], refs = [], observers = [], listeners = new Map(), storage = new Map();
  if (storedSession) storage.set('gojo_analytics_session', storedSession);
  let index = 0, cleanup, pathname = '/';
  class Element {}
  class Anchor extends Element {
    constructor(href, dataset) { super(); this.href = href; this.dataset = dataset; }
    closest() { return this; }
  }
  class Observer {
    constructor(callback) { this.callback = callback; observers.push(this); }
    observe() {}
    disconnect() { this.disconnected = true; }
  }
  const record = async (body) => events.push(JSON.parse(typeof body === 'string' ? body : await body.text()));
  const context = {
    exports: {}, URL, Blob, Element, HTMLAnchorElement: Anchor,
    IntersectionObserver: observerAvailable ? Observer : undefined,
    crypto: { randomUUID: () => '11111111-1111-4111-8111-111111111111' },
    sessionStorage: {
      getItem: (key) => { if (blockedStorage) throw Error('blocked'); return storage.get(key); },
      setItem: (key, value) => { if (blockedStorage) throw Error('blocked'); storage.set(key, value); },
    },
    process: { env: { NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN: token, NEXT_PUBLIC_POSTHOG_KEY: primaryToken, NEXT_PUBLIC_POSTHOG_HOST: host } },
    navigator: { userAgent: 'Macintosh; Intel Mac OS X', maxTouchPoints: 0, sendBeacon: (_url, body) => { if (beaconThrows) throw Error('blocked'); if (!beacon) return false; void record(body); return true; } },
    window: { location: { hostname, origin: `https://${hostname}`, pathname }, innerWidth: 1280 },
    document: { referrer: 'https://example.org/private?email=private', getElementById: () => ({}), addEventListener: (type, fn) => listeners.set(type, fn), removeEventListener: (type) => listeners.delete(type) },
    fetch: async (_url, options) => { await record(options.body); return {}; },
    require: (name) => {
      if (name === 'react') return { useRef: (initial) => { const key = index++; refs[key] ??= { current: initial }; return refs[key]; }, useEffect: (effect) => { cleanup = effect(); } };
      if (name === 'next/navigation') return { usePathname: () => pathname };
      throw Error(`Unexpected import ${name}`);
    },
  };
  vm.runInNewContext(compiled, context);
  function render(path = pathname) { cleanup?.(); pathname = path; context.window.location.pathname = path; index = 0; context.exports.default(); }
  render();
  return { events, observers, listeners, context, render, stop: () => cleanup?.(), click: (name, href, extra = {}, type = 'click', button = 0) => {
    const link = new Anchor(href, { funnelEvent: name, ...extra });
    listeners.get(type)?.({ type, button, target: link });
    return link;
  } };
}
const flush = () => new Promise(setImmediate);
const app = mount();
await flush();
assert.equal(app.events.length, 1);
assert.equal(app.events[0].event, '$pageview');
assert.equal(app.events[0].properties.homepage_version, 'workbench_v1');
assert.equal(app.events[0].properties.viewport_class, 'large');
assert.equal(app.events[0].properties.os_family, 'macos');
assert.equal(app.events[0].properties.referring_domain, 'example.org');
app.observers[0].callback([{ isIntersecting: false }]);
app.observers[0].callback([{ isIntersecting: true }]);
app.observers[0].callback([{ isIntersecting: true }]);
const purchase = app.click('pricing_cta_clicked', 'https://buy.stripe.com/example?discount=private#private', { funnelPlan: 'personal_lifetime' });
assert.match(purchase.href, /client_reference_id=gojo_11111111/);
app.click('download_cta_clicked', 'https://downloads.trygojo.com/Gojo.dmg?secret=private#private', { funnelPlacement: 'hero', funnelPlan: 'invalid value' });
app.click('unknown_event', 'https://example.org/');
app.click('pricing_cta_clicked', 'https://evil.example/');
app.click('download_cta_clicked', 'javascript:alert(1)');
app.click('download_cta_clicked', 'https://example.org/', {}, 'auxclick', 2);
await flush();
assert.deepEqual(app.events.map(({ event }) => event), ['$pageview', 'pricing_section_viewed', 'pricing_cta_clicked', 'download_cta_clicked']);
assert.equal(app.events[2].properties.destination, 'https://buy.stripe.com/example');
assert.equal(app.events[3].properties.destination, 'https://downloads.trygojo.com/Gojo.dmg');
assert.equal(app.events[3].properties.plan, undefined);
assert.equal(app.events[2].properties.distinct_id, app.events[3].properties.distinct_id);
assert.ok(!JSON.stringify(app.events).includes('private'));
app.render();
app.observers.at(-1).callback([{ isIntersecting: true }]);
await flush();
assert.equal(app.events.length, 4, 'effect replay must not duplicate pageview or pricing exposure');
app.context.window.innerWidth = 600;
app.render('/features');
await flush();
assert.equal(app.events.at(-1).properties.homepage_version, undefined);
assert.equal(app.events.at(-1).properties.viewport_class, 'small');
app.render('/');
app.observers.at(-1).callback([{ isIntersecting: true }]);
await flush();
assert.equal(app.events.filter(({ event }) => event === 'pricing_section_viewed').length, 2);
app.stop();
assert.equal(app.listeners.size, 0);
assert.equal(app.observers.at(-1).disconnected, true);
for (const hostname of ['localhost', '127.0.0.1', '[::1]', 'preview.localhost']) {
  const local = mount({ hostname });
  await flush();
  assert.equal(local.events.length, 0);
  assert.equal(local.listeners.size, 0);
}
assert.equal(mount({ token: '' }).listeners.size, 0);
const fallback = mount({ beacon: false, blockedStorage: true, observerAvailable: false });
fallback.click('download_cta_clicked', 'https://example.org/Gojo.dmg');
await flush();
assert.equal(fallback.events.length, 2);
assert.equal(fallback.events[0].properties.distinct_id, fallback.events[1].properties.distinct_id);
assert.equal(fallback.observers.length, 0);
const production = mount({ primaryToken: 'production-project', token: 'legacy-project' });
const middleClick = production.click('pricing_cta_clicked', 'https://buy.stripe.com/checkout?discount=keep#keep', { funnelPlan: 'personal_lifetime', funnelPlacement: 'pricing' }, 'auxclick', 1);
await flush();
assert.equal(production.events[0].api_key, 'production-project');
assert.equal(new URL(middleClick.href).searchParams.get('client_reference_id'), production.events[0].properties.distinct_id);
assert.equal(new URL(middleClick.href).searchParams.get('discount'), 'keep');
assert.equal(new URL(middleClick.href).hash, '#keep');
assert.equal(production.events.at(-1).properties.placement, 'pricing');
assert.equal(production.events.at(-1).event, 'pricing_cta_clicked');
const invalidSession = mount({ storedSession: '11111111-1111-1111-1111-111111111111', beaconThrows: true });
await flush();
assert.equal(invalidSession.events[0].properties.distinct_id, 'gojo_11111111-1111-4111-8111-111111111111');
for (const host of ['http://capture.example', 'invalid-host']) {
  const invalidHost = mount({ host });
  await flush();
  assert.equal(invalidHost.events.length, 0);
  assert.equal(invalidHost.listeners.size, 0);
}
console.log('Funnel analytics passed. Finite events, context, privacy, attribution, exposure deduplication, localhost exclusion, fallback transport, and cleanup verified.');

const readSource = (path) => readFileSync(resolve(path), "utf8")
const layout = readSource("app/layout.tsx")
const analytics = readSource("components/funnel-analytics.tsx")
const home = readSource("app/page.tsx")
const worker = readSource("worker.mjs")
const privacy = readSource("app/privacy/page.tsx")
const readme = readSource("README.md")

if ((layout.match(/<FunnelAnalytics \/>/g) ?? []).length !== 1) {
  throw new Error("root layout must mount FunnelAnalytics exactly once so every marketing page records pageviews")
}

for (const required of [
  '"$pageview"',
  "data-funnel-event",
  "NEXT_PUBLIC_POSTHOG_KEY",
  "NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN",
  "NEXT_PUBLIC_POSTHOG_HOST",
  "navigator.sendBeacon",
  "usePathname",
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

function verifyDownloadLinks(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name)
    if (entry.isDirectory()) verifyDownloadLinks(path)
    else if (entry.name.endsWith(".html")) {
      const page = parse(readFileSync(path, "utf8"))
      for (const link of page.querySelectorAll("a[href]")) {
        const href = link.getAttribute("href")
        if (!/^https:\/\/downloads\.trygojo\.com\/Gojo(?:-[\d.]+)?\.dmg$/.test(href)) continue
        if (link.getAttribute("data-funnel-event") !== "download_cta_clicked") {
          throw new Error(`${path}: untracked direct download ${href}`)
        }
      }
    }
  }
}

verifyDownloadLinks("out")
console.log("funnel analytics and rendered download coverage passed")
