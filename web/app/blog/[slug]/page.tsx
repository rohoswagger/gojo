import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { POST_SLUGS, loadPost } from "../lib";

export function generateStaticParams() {
  return POST_SLUGS.map((slug) => ({ slug }));
}

type Params = { params: Promise<{ slug: string }> };

export async function generateMetadata({
  params,
}: Params): Promise<Metadata> {
  const { slug } = await params;
  if (!POST_SLUGS.includes(slug as (typeof POST_SLUGS)[number])) {
    return {};
  }
  const post = loadPost(slug);
  const { article } = post;

  return {
    title: post.title ?? undefined,
    description: post.description ?? undefined,
    alternates: post.canonical ? { canonical: post.canonical } : undefined,
    authors: article.author ? [{ name: article.author }] : undefined,
    robots: article.robots ?? undefined,
    openGraph: {
      title: post.og["og:title"],
      description: post.og["og:description"],
      type: "article",
      url: post.og["og:url"],
      images: post.og["og:image"]
        ? [
            {
              url: post.og["og:image"],
              alt: post.og["og:image:alt"],
            },
          ]
        : undefined,
      publishedTime: article.published_time ?? undefined,
      modifiedTime: article.modified_time ?? undefined,
      section: article.section ?? undefined,
    },
    twitter: {
      // Four source posts omit twitter:card entirely. Next still emits a
      // twitter block for the title/description/image, and its default card
      // is the small "summary" — which would downgrade those four relative to
      // the other eleven. Every post has an og:image, so large is correct.
      card:
        (post.twitter["twitter:card"] as "summary_large_image") ??
        "summary_large_image",
      title: post.twitter["twitter:title"],
      description: post.twitter["twitter:description"],
      images: post.twitter["twitter:image"]
        ? [post.twitter["twitter:image"]]
        : undefined,
    },
  };
}

export default async function BlogPostPage({ params }: Params) {
  const { slug } = await params;
  if (!POST_SLUGS.includes(slug as (typeof POST_SLUGS)[number])) {
    notFound();
  }
  const post = loadPost(slug);

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(post.jsonLd) }}
      />
      <div
        className={post.bodyClass ?? undefined}
        dangerouslySetInnerHTML={{ __html: post.bodyHtml }}
      />
    </>
  );
}
