import type { Metadata } from "next"
import { notFound } from "next/navigation"

import { SiteFooterLegacy } from "@/components/site-footer-legacy"
import {
  alternativeArticleBody,
  alternativeArticleSchema,
  alternativeCanonical,
  alternativeDescription,
  alternativeTitle,
  getAlternative,
  getAlternatives,
} from "@/lib/alternatives"

export function generateStaticParams() {
  return getAlternatives().map((alternative) => ({ slug: alternative.slug }))
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>
}): Promise<Metadata> {
  const { slug } = await params
  const alternative = getAlternative(slug)
  if (!alternative) return {}

  const title = alternativeTitle(alternative)
  const description = alternativeDescription(alternative)
  const canonical = alternativeCanonical(alternative)

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

export default async function AlternativePage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params
  const alternative = getAlternative(slug)
  if (!alternative) notFound()

  const schema = alternativeArticleSchema(alternative)
  const body = alternativeArticleBody(alternative)

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
