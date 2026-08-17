import * as React from "react"
import Link from "next/link"

import type { Block, Inline } from "@/app/blog/lib"

/** Internal routes go through next/link; anything else stays a plain anchor. */
function Anchor({
  href,
  children,
  ...props
}: React.ComponentProps<"a"> & { href: string }) {
  if (href.startsWith("/")) {
    return (
      <Link href={href} {...props}>
        {children}
      </Link>
    )
  }
  return (
    <a href={href} rel={href.startsWith("http") ? "noopener" : undefined} {...props}>
      {children}
    </a>
  )
}

/** Renders a paragraph's inline runs: text, links, strong, em. */
function Runs({ content }: { content: Inline[] }) {
  return (
    <>
      {content.map((run, i) => {
        switch (run.t) {
          case "link":
            return (
              <Anchor key={i} href={run.href!}>
                {run.s}
              </Anchor>
            )
          case "strong":
            return <strong key={i}>{run.s}</strong>
          case "em":
            return <em key={i}>{run.s}</em>
          default:
            return <React.Fragment key={i}>{run.s}</React.Fragment>
        }
      })}
    </>
  )
}

function AnswerBox({ block }: { block: Extract<Block, { type: "answer" }> }) {
  return (
    <aside className="answer-box">
      {block.label ? <p className="answer-label">{block.label}</p> : null}
      {block.copy ? <p className="answer-copy">{block.copy}</p> : null}
      {block.points.length ? (
        <ul className="answer-points">
          {block.points.map((point) => (
            <li key={point}>{point}</li>
          ))}
        </ul>
      ) : null}
    </aside>
  )
}

function ComparisonTable({ block }: { block: Extract<Block, { type: "table" }> }) {
  return (
    <div className="table-scroll">
      <table className="comparison-table">
        <thead>
          <tr>
            {block.head.map((cell) => (
              <th key={cell} scope="col">
                {cell}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {block.rows.map((row, i) => (
            <tr key={i}>
              {row.map((cell, j) => (
                <td key={j}>{cell}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/**
 * FAQ entries stay expanded rather than collapsing into an accordion: each
 * post ships FAQPage JSON-LD, and the answers should be in the rendered text
 * for the crawler that reads it.
 */
function Faq({ block }: { block: Extract<Block, { type: "faq" }> }) {
  return (
    <section className="faq-list">
      {block.items.map((item) => (
        <React.Fragment key={item.q}>
          <h3>{item.q}</h3>
          {item.a.map((para, i) => (
            <p key={i}>
              <Runs content={para} />
            </p>
          ))}
        </React.Fragment>
      ))}
    </section>
  )
}

function ArticleCta({ block }: { block: Extract<Block, { type: "cta" }> }) {
  return (
    <section className="article-cta">
      {block.label ? <p className="answer-label">{block.label}</p> : null}
      <h2>{block.title}</h2>
      {block.copy ? <p>{block.copy}</p> : null}
      <div className="article-cta-actions">
        {block.actions.map((action) => (
          <Anchor
            key={action.href}
            href={action.href}
            className={action.primary ? "btn btn-primary" : "article-cta-link"}
          >
            {action.label}
          </Anchor>
        ))}
      </div>
      {block.trust ? <p className="article-cta-trust">{block.trust}</p> : null}
    </section>
  )
}

function ArticleNext({ block }: { block: Extract<Block, { type: "next" }> }) {
  return (
    <section className="article-next">
      {block.label ? <p className="answer-label">{block.label}</p> : null}
      <h2>{block.title}</h2>
      {block.copy ? (
        <p>
          <Runs content={block.copy} />
        </p>
      ) : null}
      {block.links.length ? (
        <p className="related-links">
          {block.links.map((link) => (
            <Anchor key={link.href} href={link.href}>
              {link.label}
            </Anchor>
          ))}
        </p>
      ) : null}
    </section>
  )
}

function MiniCards({ block }: { block: Extract<Block, { type: "miniCards" }> }) {
  return (
    <ul className="comparison-mini-grid">
      {block.cards.map((card) => (
        <li key={card.href}>
          <Anchor href={card.href} className="comparison-mini-card">
            {card.name ? <span>{card.name}</span> : null}
            <strong>{card.title}</strong>
            <em>{card.copy}</em>
          </Anchor>
        </li>
      ))}
    </ul>
  )
}

function BlockView({ block }: { block: Block }) {
  switch (block.type) {
    case "answer":
      return <AnswerBox block={block} />

    case "jumpNav":
      return (
        <nav className="article-jump-nav" aria-label="On this page">
          <span>{block.label}</span>
          {block.items.map((item) => (
            <a key={item.href} href={item.href}>
              {item.label}
            </a>
          ))}
        </nav>
      )

    case "heading":
      return block.level === 2 ? (
        <h2 id={block.id}>{block.text}</h2>
      ) : (
        <h3 id={block.id}>{block.text}</h3>
      )

    case "paragraph":
      return (
        <p>
          <Runs content={block.content} />
        </p>
      )

    case "note":
      return (
        <p className="audit-note">
          <Runs content={block.content} />
        </p>
      )

    case "list":
      return block.ordered ? (
        <ol>
          {block.items.map((item, i) => (
            <li key={i}>
              <Runs content={item} />
            </li>
          ))}
        </ol>
      ) : (
        <ul>
          {block.items.map((item, i) => (
            <li key={i}>
              <Runs content={item} />
            </li>
          ))}
        </ul>
      )

    case "sourceFacts":
      return (
        <ul className="source-facts">
          {block.items.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      )

    case "table":
      return <ComparisonTable block={block} />

    case "faq":
      return <Faq block={block} />

    case "miniCards":
      return <MiniCards block={block} />

    case "cta":
      return <ArticleCta block={block} />

    case "next":
      return <ArticleNext block={block} />
  }
}

export function ArticleBlocks({ blocks }: { blocks: Block[] }) {
  return (
    <>
      {blocks.map((block, i) => (
        <BlockView key={i} block={block} />
      ))}
    </>
  )
}
