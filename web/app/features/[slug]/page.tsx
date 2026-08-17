import type { Metadata } from "next"
import { notFound } from "next/navigation"

import { GojoFooter } from "@/components/gojo-footer"
import {
  featureArticleBody,
  featureArticleSchema,
  featureCanonical,
  featureDescription,
  featureTitle,
  getFeature,
  getFeatures,
} from "@/lib/features"

export function generateStaticParams() {
  return getFeatures().map((feature) => ({ slug: feature.slug }))
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>
}): Promise<Metadata> {
  const { slug } = await params
  const feature = getFeature(slug)
  if (!feature) return {}

  const title = featureTitle(feature)
  const description = featureDescription(feature)
  const canonical = featureCanonical(feature)

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

export default async function FeaturePage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params
  const feature = getFeature(slug)
  if (!feature) notFound()

  const schema = featureArticleSchema(feature)
  const body = featureArticleBody(feature)

  return (
    <div className="article-shell">
      <div dangerouslySetInnerHTML={{ __html: body }} />
      <GojoFooter />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(schema) }}
      />
    </div>
  )
}
