import type { MetadataRoute } from "next";
import alternatives from "@/content/alternatives.json";
import features from "@/content/features.json";
import lastmod from "@/content/lastmod.json";

const SITE = "https://trygojo.com";

// The old site's sitemap was maintained by hand. These are its exact lastmod
// values, keyed by path, so the migration doesn't churn every date and tell
// crawlers 44 pages changed at once.
const LASTMOD = lastmod as Record<string, string>;

// Blog posts are hand-authored HTML; their slugs live in the extracted content.
const BLOG_SLUGS = Object.keys(LASTMOD)
  .filter((p) => p.startsWith("/blog/") && p !== "/blog/")
  .map((p) => p.replace(/^\/blog\/|\/$/g, ""));

function entry(path: string): MetadataRoute.Sitemap[number] {
  return {
    url: `${SITE}${path}`,
    ...(LASTMOD[path] ? { lastModified: LASTMOD[path] } : {}),
  };
}

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = [
    "/",
    "/blog/",
    ...BLOG_SLUGS.map((s) => `/blog/${s}/`),
    "/alternatives/",
    ...(alternatives.alternatives as { slug: string }[]).map(
      (a) => `/alternatives/${a.slug}/`,
    ),
    "/features/",
    ...(features.features as { slug: string }[]).map(
      (f) => `/features/${f.slug}/`,
    ),
    // Machine-readable pages that are deliberately in the sitemap.
    "/pricing.md",
    "/okf/index.md",
    "/okf/blog-comparisons.md",
  ];

  return paths.map(entry);
}
