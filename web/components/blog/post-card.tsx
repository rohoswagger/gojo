import Link from "next/link"

import { Poster } from "@/components/blog/poster"
import type { PostCard } from "@/app/blog/lib"

/**
 * One archive card: poster, topic and date, title, summary, reading time.
 * Shared by the /blog grid and the "Continue reading" row at the foot of a
 * post, so both stay identical without the article page importing the client
 * filter component.
 */
export function PostCardLink({ post }: { post: PostCard }) {
  return (
    <Link className="blog-post-card" href={`/blog/${post.slug}/`}>
      <Poster lines={post.poster} />

      <span className="blog-card-topline">
        <span className="card-topic">{post.topic}</span>
        <span className="card-dot" aria-hidden="true">
          ·
        </span>
        <time className="card-date" dateTime={post.dateISO}>
          {post.date}
        </time>
      </span>

      <h3>{post.title}</h3>
      <span className="blog-card-summary">{post.summary}</span>

      <span className="blog-post-action">
        {post.readTime ?? "Read the post"}
        {post.sourced ? (
          <span className="card-sourced">
            <SourcedMark />
            Sources checked
          </span>
        ) : null}
      </span>
    </Link>
  )
}

/** A checked seal, drawn rather than borrowed from a glyph. */
function SourcedMark() {
  return (
    <svg viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <path
        d="M8 1.4l1.94 1.02 2.16-.25.82 2.03 1.76 1.28-.98 1.94.25 2.16-2.03.82-1.28 1.76-1.94-.98-2.16.25-.82-2.03L3.8 10.1l.98-1.94-.25-2.16 2.03-.82L7.84 3.4z"
        stroke="currentColor"
        strokeWidth="1.15"
        strokeLinejoin="round"
      />
      <path
        d="M5.85 8.05l1.5 1.5 3-3.2"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}
