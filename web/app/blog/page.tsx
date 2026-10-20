import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

import { GojoFooter } from "@/components/gojo-footer";
import { GojoHeader } from "@/components/gojo-header";
import { Button } from "@/components/ui/button";
import { GOJO_RELEASE } from "@/lib/release.mjs";
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
    <div className="marketing-shell blog-shell" data-gojo-editorial="warm">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(hub.jsonLd) }}
      />

      <GojoHeader />

      <main id="main-content" tabIndex={-1} className="blog-main">
        <section className="blog-hero">
          <div className="wrap blog-hero-layout">
            <div className="blog-hero-copy">
              <h1>{hub.hero.title}</h1>
              {hub.hero.summary ? <p>{hub.hero.summary}</p> : null}
              <Button asChild size="lg" className="btn btn-primary">
                <a
                  href={GOJO_RELEASE.downloadUrl}
                  data-funnel-event="download_cta_clicked"
                  data-funnel-placement="blog_index"
                >
                  Try Gojo free for 3 days
                </a>
              </Button>
            </div>
            <figure className="blog-product-figure">
              <Image
                src="/screenshots/media.png"
                width={1308}
                height={392}
                alt="Gojo music controls in the MacBook notch, with album artwork, playback buttons and a scrubber."
              />
            </figure>
          </div>
        </section>

        <section className="blog-archive" aria-labelledby="blog-archive-heading">
          <div className="wrap">
            <div className="archive-head">
              <div>
                <h2 id="blog-archive-heading">{hub.archive.title}</h2>
              </div>
              <span>{hub.posts.length} posts</span>
            </div>

            <ol className="blog-posts">
              {hub.posts.map((post) => (
                <li key={post.slug}>
                  <Link className="blog-post-card" href={`/blog/${post.slug}/`}>
                    <span className="blog-card-topline">
                      <span>{post.kicker}</span>
                      <span>{post.date}</span>
                    </span>
                    <h3>{post.title}</h3>
                    <span className="blog-card-summary">{post.summary}</span>
                    <span className="blog-post-action" aria-hidden="true">
                      Read the post &rarr;
                    </span>
                  </Link>
                </li>
              ))}
            </ol>
          </div>
        </section>
      </main>

      <GojoFooter />
    </div>
  );
}
