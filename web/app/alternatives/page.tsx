import type { Metadata } from "next"

import { SiteFooterLegacy } from "@/components/site-footer-legacy"
import {
  alternativeHubBody,
  alternativeHubSchema,
  hubCanonical,
  hubDescription,
  hubTitle,
} from "@/lib/alternatives"

export function generateMetadata(): Metadata {
  const title = hubTitle()
  const description = hubDescription()
  const canonical = hubCanonical()

  return {
    title,
    description,
    alternates: { canonical },
    openGraph: {
      title,
      description,
      type: "article",
      url: canonical,
      images: ["/assets/og.jpg"],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: ["/assets/og.jpg"],
    },
  }
}

export default function AlternativesHubPage() {
  const schema = alternativeHubSchema()
  const body = alternativeHubBody()

  return (
    <div className="article-shell">
      <div dangerouslySetInnerHTML={{ __html: body }} />
      <SiteFooterLegacy />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
      />
    </div>
  )
}
