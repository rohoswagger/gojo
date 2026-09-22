const CANONICAL_HOST = "trygojo.com"
const LEGACY_HOST = `www.${CANONICAL_HOST}`
const LEGACY_PATHS = new Set([
  "/blog/how-to-choose-a-macbook-notch-app/",
  "/blog/best-macbook-notch-apps/",
])
const NOTCH_GUIDE_PATH = "/blog/best-mac-notch-apps-for-productivity/"
const STRIPE_WEBHOOK_PATH = "/api/stripe/webhook"
const STRIPE_PURCHASE_EVENTS = new Set([
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
])
const POSTHOG_CAPTURE_ENDPOINT = "https://us.i.posthog.com/capture/"
const SIGNATURE_TOLERANCE_SECONDS = 300
const GOJO_REFERENCE_PATTERN = /^gojo_([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i

function jsonResponse(body, status) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  })
}

function hexToBytes(value) {
  if (!/^[0-9a-f]{64}$/i.test(value)) return null
  return Uint8Array.from(value.match(/.{2}/g), (byte) => Number.parseInt(byte, 16))
}

async function verifyStripeSignature(body, header, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!header) return false

  const parts = header.split(",")
  const timestampText = parts.find((part) => part.startsWith("t="))?.slice(2)
  const signatures = parts.filter((part) => part.startsWith("v1=")).map((part) => part.slice(3))
  const timestamp = Number(timestampText)
  if (!Number.isInteger(timestamp) || Math.abs(nowSeconds - timestamp) > SIGNATURE_TOLERANCE_SECONDS) {
    return false
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  )
  const signedPayload = new TextEncoder().encode(`${timestamp}.${body}`)
  for (const signature of signatures) {
    const bytes = hexToBytes(signature)
    if (bytes && (await crypto.subtle.verify("HMAC", key, bytes, signedPayload))) return true
  }
  return false
}

function purchaseProperties(event) {
  const checkout = event.data?.object ?? {}
  const reference = typeof checkout.client_reference_id === "string" ? checkout.client_reference_id : ""
  const match = reference.match(GOJO_REFERENCE_PATTERN)
  const attributed = Boolean(match)
  const amountTotal = Number.isInteger(checkout.amount_total) ? checkout.amount_total : null

  return {
    distinct_id: attributed ? reference : `gojo_purchase_${event.id}`,
    ...(attributed ? { $session_id: match[1] } : {}),
    $insert_id: event.id,
    $process_person_profile: false,
    source: "stripe_webhook",
    checkout_mode: typeof checkout.mode === "string" ? checkout.mode : "unknown",
    payment_status: typeof checkout.payment_status === "string" ? checkout.payment_status : "unknown",
    attributed,
    ...(typeof checkout.currency === "string" ? { currency: checkout.currency } : {}),
    ...(amountTotal !== null ? { value: amountTotal / 100 } : {}),
  }
}

async function handleStripeWebhook(request, env) {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: { Allow: "POST" } })
  }
  if (!env.STRIPE_WEBHOOK_SECRET || !env.POSTHOG_API_KEY) {
    return jsonResponse({ error: "Webhook analytics is not configured" }, 500)
  }

  const body = await request.text()
  if (body.length > 1_000_000) return jsonResponse({ error: "Payload too large" }, 413)

  const valid = await verifyStripeSignature(
    body,
    request.headers.get("Stripe-Signature"),
    env.STRIPE_WEBHOOK_SECRET
  )
  if (!valid) return jsonResponse({ error: "Invalid signature" }, 400)

  let event
  try {
    event = JSON.parse(body)
  } catch {
    return jsonResponse({ error: "Invalid payload" }, 400)
  }

  if (!STRIPE_PURCHASE_EVENTS.has(event.type) || event.data?.object?.payment_status !== "paid") {
    return jsonResponse({ received: true }, 200)
  }

  const captureResponse = await globalThis.fetch(POSTHOG_CAPTURE_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      api_key: env.POSTHOG_API_KEY,
      event: "purchase_completed",
      properties: purchaseProperties(event),
    }),
  })
  if (!captureResponse.ok) {
    return jsonResponse({ error: "Analytics delivery failed" }, 500)
  }

  return jsonResponse({ received: true }, 200)
}

const worker = {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.hostname.toLowerCase() === CANONICAL_HOST && url.pathname === STRIPE_WEBHOOK_PATH) {
      return handleStripeWebhook(request, env)
    }

    const isLegacyHost = url.hostname.toLowerCase() === LEGACY_HOST
    const normalizedPath = url.pathname.endsWith("/") ? url.pathname : `${url.pathname}/`
    const isLegacyNotchGuide = LEGACY_PATHS.has(normalizedPath)

    if (isLegacyHost || isLegacyNotchGuide) {
      url.hostname = CANONICAL_HOST
      if (isLegacyNotchGuide) url.pathname = NOTCH_GUIDE_PATH
      return Response.redirect(url.toString(), 301)
    }

    return env.ASSETS.fetch(request)
  },
}

export default worker
