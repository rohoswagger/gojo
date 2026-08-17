import { readFileSync } from "node:fs";
import path from "node:path";

export type ArticleMeta = {
  published_time: string | null;
  modified_time: string | null;
  section: string | null;
  author: string | null;
  robots: string | null;
};

/** An inline run inside a paragraph, list item or note. */
export type Inline = {
  t: "text" | "link" | "strong" | "em";
  s: string;
  href?: string;
};

export type Block =
  | { type: "answer"; label: string | null; copy: string | null; points: string[] }
  | { type: "jumpNav"; label: string; items: { label: string; href: string }[] }
  | { type: "heading"; level: 2 | 3; text: string; id: string }
  | { type: "paragraph"; content: Inline[] }
  | { type: "note"; content: Inline[] }
  | { type: "list"; ordered: boolean; items: Inline[][] }
  | { type: "sourceFacts"; items: string[] }
  | { type: "table"; head: string[]; rows: string[][] }
  | { type: "faq"; items: { q: string; a: Inline[][] }[] }
  | {
      type: "miniCards";
      cards: { name: string | null; title: string; copy: string; href: string }[];
    }
  | {
      type: "cta";
      label: string | null;
      title: string;
      copy: string;
      actions: { label: string; href: string; primary: boolean }[];
      trust: string | null;
    }
  | {
      type: "next";
      label: string | null;
      title: string;
      copy: Inline[] | null;
      links: { label: string; href: string }[];
    };

export type ArticleHero = {
  label: string | null;
  title: string;
  summary: string | null;
  meta: string[];
  breadcrumb: { label: string; href: string }[];
};

type PostMeta = {
  slug: string;
  title: string | null;
  description: string | null;
  canonical: string | null;
  og: Record<string, string>;
  twitter: Record<string, string>;
  article: ArticleMeta;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  jsonLd: any;
};

export type BlogPost = PostMeta & {
  hero: ArticleHero;
  blocks: Block[];
};

/** Summary card for one post, as shown on the /blog index. */
export type PostCard = {
  slug: string;
  kicker: string | null;
  date: string | null;
  title: string;
  summary: string;
};

export type BlogHub = PostMeta & {
  hero: { label: string | null; title: string; summary: string | null };
  archive: { kicker: string | null; title: string | null };
  posts: PostCard[];
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

export function loadHub(): BlogHub {
  const file = path.join(CONTENT_DIR, "_hub.json");
  return JSON.parse(readFileSync(file, "utf8"));
}
