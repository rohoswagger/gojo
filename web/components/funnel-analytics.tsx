"use client";

import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";

type FunnelEvent = "download_cta_clicked" | "pricing_cta_clicked";
type CaptureEvent = "$pageview" | "pricing_section_viewed" | FunnelEvent;
type ViewportClass = "small" | "medium" | "large";
type OsFamily = "macos" | "ios" | "windows" | "android" | "linux" | "other";
type CaptureLabels = { plan?: string; placement?: string; destination?: string };

type CaptureProperties = {
  distinct_id: string;
  $session_id: string;
  $process_person_profile: false;
  $current_url: string;
  page_path: string;
  site_version: "trial_first_v1";
  homepage_version?: "workbench_v1";
  viewport_class: ViewportClass;
  os_family: OsFamily;
  referring_domain?: string;
  plan?: string;
  placement?: string;
  destination?: string;
};

let fallbackSession: string | undefined;

function getSessionId(): string {
  try {
    const stored = sessionStorage.getItem("gojo_analytics_session");
    if (stored && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(stored)) return stored;
    const session = fallbackSession ?? crypto.randomUUID();
    fallbackSession = session;
    sessionStorage.setItem("gojo_analytics_session", session);
    return session;
  } catch {
    fallbackSession ??= crypto.randomUUID();
    return fallbackSession;
  }
}

function boundedLabel(value: string | undefined): string | undefined {
  return value && /^[a-z0-9_-]{1,64}$/i.test(value) ? value : undefined;
}

function getOsFamily(): OsFamily {
  const agent = navigator.userAgent;
  if (/iPhone|iPad|iPod/i.test(agent) || (/Macintosh/i.test(agent) && navigator.maxTouchPoints > 1)) return "ios";
  if (/Macintosh|Mac OS X/i.test(agent)) return "macos";
  if (/Windows/i.test(agent)) return "windows";
  if (/Android/i.test(agent)) return "android";
  if (/Linux/i.test(agent)) return "linux";
  return "other";
}

function referringDomain(): string | undefined {
  try {
    const referrer = new URL(document.referrer);
    if (referrer.protocol === "https:" || referrer.protocol === "http:") return referrer.hostname;
  } catch {
    return undefined;
  }
}

export function FunnelAnalytics() {
  const pathname = usePathname();
  const lastPageview = useRef<string | null>(null);
  const pricingViewed = useRef(false);

  useEffect(() => {
    const token = process.env.NEXT_PUBLIC_POSTHOG_KEY || process.env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN;
    const hostname = window.location.hostname;
    if (!token || hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]" || hostname.endsWith(".localhost")) return;

    let endpoint: URL;
    try {
      const host = process.env.NEXT_PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com";
      endpoint = new URL(`${host.replace(/\/+$/, "")}/capture/`);
      if (endpoint.protocol !== "https:") return;
    } catch {
      return;
    }

    const sessionId = getSessionId();
    const capture = (event: CaptureEvent, labels: CaptureLabels = {}) => {
      const properties: CaptureProperties = {
        distinct_id: `gojo_${sessionId}`,
        $session_id: sessionId,
        $process_person_profile: false,
        $current_url: `${window.location.origin}${window.location.pathname}`,
        page_path: window.location.pathname,
        site_version: "trial_first_v1",
        homepage_version: pathname === "/" ? "workbench_v1" : undefined,
        viewport_class: window.innerWidth < 768 ? "small" : window.innerWidth < 1024 ? "medium" : "large",
        os_family: getOsFamily(),
        referring_domain: referringDomain(),
        ...labels,
      };
      const body = JSON.stringify({ api_key: token, event, properties });
      try {
        if (navigator.sendBeacon?.(endpoint.href, new Blob([body], { type: "application/json" }))) return;
      } catch {
        // Beacon can be blocked independently of fetch by browser policy.
      }
      void fetch(endpoint.href, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        keepalive: true,
      }).catch(() => {});
    };

    if (lastPageview.current !== pathname) {
      lastPageview.current = pathname;
      pricingViewed.current = false;
      capture("$pageview");
    }

    const pricingSection = document.getElementById("buy");
    const observer = pricingSection && typeof IntersectionObserver !== "undefined"
      ? new IntersectionObserver((entries) => {
          if (!pricingViewed.current && entries.some((entry) => entry.isIntersecting)) {
            pricingViewed.current = true;
            capture("pricing_section_viewed");
            observer?.disconnect();
          }
        }, { threshold: 0.1 })
      : undefined;
    if (pricingSection) observer?.observe(pricingSection);

    const onClick = (event: MouseEvent) => {
      if (event.type === "auxclick" && event.button !== 1) return;
      if (!(event.target instanceof Element)) return;
      const link = event.target.closest("a[data-funnel-event]");
      if (!(link instanceof HTMLAnchorElement)) return;
      const name = link.dataset.funnelEvent;
      if (name !== "download_cta_clicked" && name !== "pricing_cta_clicked") return;
      const destination = new URL(link.href);
      if (destination.protocol !== "https:" && destination.protocol !== "http:") return;
      if (name === "pricing_cta_clicked") {
        if (destination.protocol !== "https:" || destination.hostname !== "buy.stripe.com") return;
        destination.searchParams.set("client_reference_id", `gojo_${sessionId}`);
        link.href = destination.href;
      }
      capture(name, {
        plan: boundedLabel(link.dataset.funnelPlan),
        placement: boundedLabel(link.dataset.funnelPlacement),
        destination: `${destination.origin}${destination.pathname}`,
      });
    };

    document.addEventListener("click", onClick);
    document.addEventListener("auxclick", onClick);
    return () => {
      observer?.disconnect();
      document.removeEventListener("click", onClick);
      document.removeEventListener("auxclick", onClick);
    };
  }, [pathname]);

  return null;
}

export default FunnelAnalytics;
