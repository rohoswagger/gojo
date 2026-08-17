import type { Metadata } from "next";
import Link from "next/link";

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
    <div className="blog-shell">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(hub.jsonLd) }}
      />

      <GojoHeader />

      <main className="blog-main">
        <section className="blog-hero">
          <div className="wrap">
            {hub.hero.label ? <p className="blog-label">{hub.hero.label}</p> : null}
            <h1>{hub.hero.title}</h1>
            {hub.hero.summary ? <p>{hub.hero.summary}</p> : null}
          </div>
        </section>

        <section className="blog-archive" aria-labelledby="blog-archive-heading">
          <div className="wrap">
            <div className="archive-head">
              <div>
                {hub.archive.kicker ? (
                  <p className="archive-kicker">{hub.archive.kicker}</p>
                ) : null}
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
