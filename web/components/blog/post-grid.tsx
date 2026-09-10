"use client"

import { useState, type CSSProperties } from "react"

import { PostCardLink } from "@/components/blog/post-card"
import type { PostCard } from "@/app/blog/lib"

/**
 * The archive: topic filter, live count, and the poster grid.
 *
 * Filtering is client-side because the whole archive is 40 records and the
 * site is a static export — a round trip per topic would be slower and would
 * cost a route each. The grid is keyed on the active topic so React remounts
 * it, which replays the stagger in app/blog-paper.css and makes the change
 * legible instead of instantaneous.
 */
export function PostGrid({ posts }: { posts: PostCard[] }) {
  const [topic, setTopic] = useState<string | null>(null)

  const counts = new Map<string, number>()
  for (const post of posts) {
    counts.set(post.topic, (counts.get(post.topic) ?? 0) + 1)
  }
  const topics = [...counts.entries()].sort((a, b) => b[1] - a[1])

  const shown = topic ? posts.filter((post) => post.topic === topic) : posts

  return (
    <>
      <div className="topic-filter" role="group" aria-label="Filter posts by topic">
        <button
          type="button"
          className="topic-chip"
          aria-pressed={topic === null}
          onClick={() => setTopic(null)}
        >
          All posts
          <span className="topic-chip-count">{posts.length}</span>
        </button>
        {topics.map(([name, count]) => (
          <button
            key={name}
            type="button"
            className="topic-chip"
            aria-pressed={topic === name}
            onClick={() => setTopic(name)}
          >
            {name}
            <span className="topic-chip-count">{count}</span>
          </button>
        ))}
      </div>

      <p className="archive-count" role="status">
        {shown.length} {shown.length === 1 ? "post" : "posts"}
        {" · "}
        {topic ?? `${topics.length} topics`}
      </p>

      <ol className="blog-posts" key={topic ?? "all"}>
        {shown.map((post, i) => (
          <li key={post.slug} style={{ "--i": Math.min(i, 8) } as CSSProperties}>
            <PostCardLink post={post} />
          </li>
        ))}

        {shown.length === 0 ? (
          <li className="archive-empty">
            <p>Nothing published under {topic} yet.</p>
            <button type="button" onClick={() => setTopic(null)}>
              Show all posts
            </button>
          </li>
        ) : null}
      </ol>
    </>
  )
}
