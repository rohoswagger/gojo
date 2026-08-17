import type { MetadataRoute } from "next";

// Mirrors the old docs/robots.txt exactly: allow everything, and name the AI
// crawlers explicitly so their access is a stated choice rather than a
// side effect of the wildcard.
const AI_AND_SEARCH_AGENTS = [
  "GPTBot",
  "ChatGPT-User",
  "PerplexityBot",
  "ClaudeBot",
  "anthropic-ai",
  "Google-Extended",
  "Bingbot",
];

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/" },
      ...AI_AND_SEARCH_AGENTS.map((userAgent) => ({ userAgent, allow: "/" })),
    ],
    sitemap: "https://trygojo.com/sitemap.xml",
  };
}
