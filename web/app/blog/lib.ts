import { readFileSync } from "node:fs";
import path from "node:path";

export type ArticleMeta = {
  published_time: string | null;
  modified_time: string | null;
  section: string | null;
  author: string | null;
  robots: string | null;
};

export type BlogPost = {
  slug: string;
  title: string | null;
  description: string | null;
  canonical: string | null;
  og: Record<string, string>;
  twitter: Record<string, string>;
  article: ArticleMeta;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  jsonLd: any;
  bodyClass: string | null;
  bodyHtml: string;
};

const CONTENT_DIR = path.join(process.cwd(), "content", "blog");

export const POST_SLUGS = [
  "best-droppy-alternatives",
  "best-macos-accessibility-permission-apps",
  "best-macos-notch-utilities",
  "gojo-vs-alcove",
  "gojo-vs-alttab",
  "gojo-vs-bettertouchtool",
  "gojo-vs-boring-notch",
  "gojo-vs-droppy",
  "gojo-vs-dynamiclake",
  "gojo-vs-flux",
  "gojo-vs-karabiner-elements",
  "gojo-vs-maccy",
  "gojo-vs-notchnook",
  "gojo-vs-raycast",
  "gojo-vs-rectangle",
] as const;

export function loadPost(slug: string): BlogPost {
  const file = path.join(CONTENT_DIR, `${slug}.json`);
  return JSON.parse(readFileSync(file, "utf8"));
}

export function loadHub(): BlogPost {
  return loadPost("_hub");
}
