import type { Metadata } from "next";

import { PostGrid } from "@/components/blog/post-grid";
import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";
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
    <div className="blog-shell blog-paper">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(hub.jsonLd) }}
      />

      <GojoHeader active="/blog/" />

      <main className="blog-main">
        <section className="blog-hero">
          <div className="wrap">
            <h1>{hub.hero.title}</h1>
            {hub.hero.summary ? (
              <p className="blog-lede">{hub.hero.summary}</p>
            ) : null}
          </div>
        </section>

        <section className="blog-archive" aria-label="All posts">
          <div className="wrap">
            <PostGrid posts={hub.posts} />
          </div>
        </section>
      </main>

      <GojoFooter />
    </div>
  );
}
