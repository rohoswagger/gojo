import type { Metadata } from "next"

import { GojoFooter } from "@/components/gojo-footer"
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
    <div className="article-shell" data-gojo-editorial="warm">
      <div dangerouslySetInnerHTML={{ __html: body }} />
      <GojoFooter />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
      />
    </div>
  )
}
