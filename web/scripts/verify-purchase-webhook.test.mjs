import assert from "node:assert/strict"
import test from "node:test"

import worker from "../worker.mjs"

const webhookUrl = "https://trygojo.com/api/stripe/webhook"
const webhookSecret = "whsec_test_only"
const posthogKey = "phc_test_only"
const sessionId = "4b4cab52-a909-4afa-9a33-9c0763027312"
const clientReferenceId = `gojo_${sessionId}`

async function signature(body, timestamp = Math.floor(Date.now() / 1000)) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(webhookSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  )
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${body}`)
  )
  const hex = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("")
  return `t=${timestamp},v1=${hex}`
}

function checkoutEvent(type = "checkout.session.completed") {
  return {
    id: "evt_test_purchase",
    type,
    data: {
      object: {
        client_reference_id: clientReferenceId,
        mode: "payment",
        payment_status: "paid",
        currency: "usd",
        amount_total: 999,
        customer_details: { email: "must-not-be-forwarded@example.com" },
      },
    },
  }
}

async function requestFor(event, signatureOverride) {
  const body = JSON.stringify(event)
  return new Request(webhookUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": signatureOverride ?? (await signature(body)),
    },
    body,
  })
}

function environment(overrides = {}) {
  return {
    ASSETS: { fetch: async () => new Response("asset", { status: 418 }) },
    POSTHOG_API_KEY: posthogKey,
    STRIPE_WEBHOOK_SECRET: webhookSecret,
    ...overrides,
  }
}

test("records a signed paid checkout without forwarding customer PII", async () => {
  const calls = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init })
    return new Response("ok", { status: 200 })
  }

  try {
    const response = await worker.fetch(await requestFor(checkoutEvent()), environment(), {})
    assert.equal(response.status, 200)
    assert.equal(calls.length, 1)
    assert.equal(calls[0].url, "https://us.i.posthog.com/capture/")

    const payload = JSON.parse(calls[0].init.body)
    assert.equal(payload.api_key, posthogKey)
    assert.equal(payload.event, "purchase_completed")
    assert.equal(payload.properties.distinct_id, clientReferenceId)
    assert.equal(payload.properties.$session_id, sessionId)
    assert.equal(payload.properties.$insert_id, "evt_test_purchase")
    assert.equal(payload.properties.$process_person_profile, false)
    assert.equal(payload.properties.value, 9.99)
    assert.equal(payload.properties.currency, "usd")
    assert.equal(JSON.stringify(payload).includes("must-not-be-forwarded@example.com"), false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("records a signed delayed-payment success", async () => {
  const event = {
    id: "evt_async_paid_123",
    type: "checkout.session.async_payment_succeeded",
    data: {
      object: {
        client_reference_id: clientReferenceId,
        mode: "payment",
        payment_status: "paid",
        currency: "usd",
        amount_total: 999,
      },
    },
  }
  const captured = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url, init) => {
    captured.push({ url: String(url), init })
    return new Response("ok", { status: 200 })
  }

  try {
    const response = await worker.fetch(await requestFor(event), environment(), {})
    assert.equal(response.status, 200)
    assert.equal(captured.length, 1)
    assert.equal(JSON.parse(captured[0].init.body).event, "purchase_completed")
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("rejects an invalid Stripe signature before capture", async () => {
  let captureCalls = 0
  const originalFetch = globalThis.fetch
  globalThis.fetch = async () => {
    captureCalls += 1
    return new Response("ok")
  }

  try {
    const response = await worker.fetch(
      await requestFor(checkoutEvent(), `t=${Math.floor(Date.now() / 1000)},v1=00`),
      environment(),
      {}
    )
    assert.equal(response.status, 400)
    assert.equal(captureCalls, 0)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("fails closed when webhook bindings are missing", async () => {
  const response = await worker.fetch(
    await requestFor(checkoutEvent()),
    environment({ POSTHOG_API_KEY: undefined }),
    {}
  )
  assert.equal(response.status, 500)
})

test("acknowledges unrelated signed Stripe events without capturing", async () => {
  let captureCalls = 0
  const originalFetch = globalThis.fetch
  globalThis.fetch = async () => {
    captureCalls += 1
    return new Response("ok")
  }

  try {
    const response = await worker.fetch(
      await requestFor(checkoutEvent("customer.created")),
      environment(),
      {}
    )
    assert.equal(response.status, 200)
    assert.equal(captureCalls, 0)
  } finally {
    globalThis.fetch = originalFetch
  }
})
