import type { Metadata } from "next";

import { loadHub } from "./lib";

const hub = loadHub();

export const metadata: Metadata = {
  title: hub.title ?? undefined,
  description: hub.description ?? undefined,
  alternates: hub.canonical ? { canonical: hub.canonical } : undefined,
  openGraph: {
    title: hub.og["og:title"],
    description: hub.og["og:description"],
    type: "website",
    url: hub.og["og:url"],
    images: hub.og["og:image"]
      ? [
          {
            url: hub.og["og:image"],
            alt: hub.og["og:image:alt"],
          },
        ]
      : undefined,
  },
  twitter: {
    card: (hub.twitter["twitter:card"] as "summary_large_image") ?? undefined,
    title: hub.twitter["twitter:title"],
    description: hub.twitter["twitter:description"],
    images: hub.twitter["twitter:image"]
      ? [hub.twitter["twitter:image"]]
      : undefined,
  },
};

export default function BlogIndexPage() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(hub.jsonLd) }}
      />
      <div
        className={hub.bodyClass ?? undefined}
        dangerouslySetInnerHTML={{ __html: hub.bodyHtml }}
      />
    </>
  );
}
