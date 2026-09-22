"use client"

import { useEffect } from "react"
import { usePathname } from "next/navigation"

const apiHost = "https://us.i.posthog.com"
const apiKey = process.env.NEXT_PUBLIC_POSTHOG_KEY
const sessionStorageKey = "gojo_analytics_session"
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

type FunnelProperties = Record<string, string | boolean>
type SessionIdentity = { distinctId: string; sessionId: string }

let volatileSessionId = ""

function urlWithoutQueryOrHash(value: string) {
  const url = new URL(value, window.location.origin)
  return `${url.origin}${url.pathname}`
}

function getSessionIdentity(): SessionIdentity {
  if (!volatileSessionId) {
    try {
      const stored = window.sessionStorage.getItem(sessionStorageKey)
      volatileSessionId = stored && uuidPattern.test(stored) ? stored : crypto.randomUUID()
      window.sessionStorage.setItem(sessionStorageKey, volatileSessionId)
    } catch {
      volatileSessionId = crypto.randomUUID()
    }
  }

  return {
    distinctId: `gojo_${volatileSessionId}`,
    sessionId: volatileSessionId,
  }
}

function decorateStripeCheckout(link: HTMLAnchorElement, distinctId: string) {
  const destination = new URL(link.href)
  if (destination.hostname !== "buy.stripe.com") return

  destination.searchParams.set("client_reference_id", distinctId)
  link.href = destination.toString()
}

function capture(event: string, properties: FunnelProperties = {}) {
  if (!apiKey) return

  const identity = getSessionIdentity()
  const payload = JSON.stringify({
    api_key: apiKey,
    event,
    properties: {
      distinct_id: identity.distinctId,
      $session_id: identity.sessionId,
      $process_person_profile: false,
      $current_url: urlWithoutQueryOrHash(window.location.href),
      ...properties,
    },
  })
  const body = new Blob([payload], { type: "application/json" })

  if (navigator.sendBeacon?.(`${apiHost}/capture/`, body)) return

  void fetch(`${apiHost}/capture/`, {
    body: payload,
    headers: { "Content-Type": "application/json" },
    keepalive: true,
    method: "POST",
  }).catch(() => {})
}

export function FunnelAnalytics() {
  const pathname = usePathname()

  useEffect(() => {
    capture("$pageview", { page_path: pathname })
  }, [pathname])

  useEffect(() => {
    const onInteraction = (event: MouseEvent) => {
      if (event.type === "auxclick" && event.button !== 1) return

      const target = event.target
      if (!(target instanceof Element)) return

      const link = target.closest<HTMLAnchorElement>("a[data-funnel-event]")
      if (!link) return

      const funnelEvent = link.dataset.funnelEvent
      if (!funnelEvent) return

      decorateStripeCheckout(link, getSessionIdentity().distinctId)
      const properties: FunnelProperties = {
        destination: urlWithoutQueryOrHash(link.href),
        page_path: window.location.pathname,
      }
      if (link.dataset.funnelPlan) properties.plan = link.dataset.funnelPlan

      capture(funnelEvent, properties)
    }

    document.addEventListener("click", onInteraction)
    document.addEventListener("auxclick", onInteraction)
    return () => {
      document.removeEventListener("click", onInteraction)
      document.removeEventListener("auxclick", onInteraction)
    }
  }, [])

  return null
}
