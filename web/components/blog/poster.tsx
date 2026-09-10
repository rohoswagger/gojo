import { Fragment } from "react"

/**
 * The typographic poster that stands in for a cover image on every post.
 *
 * Each line comes from content/blog/_hub.json and is authored, not wrapped —
 * the breaks are the composition. A single `*word*` per hook is set in the
 * serif italic, which is the only place that face appears.
 */
export function Poster({ lines }: { lines: string[] }) {
  return (
    <span className="poster">
      <span className="poster-lines">
        {lines.map((line, i) => (
          <span key={i}>{renderLine(line)}</span>
        ))}
      </span>
      <span className="poster-rule" aria-hidden="true" />
    </span>
  )
}

/** Splits `Two *scopes*.` into plain runs and one emphasised run. */
function renderLine(line: string) {
  return line.split(/\*([^*]+)\*/).map((part, i) =>
    i % 2 === 1 ? (
      <em key={i} className="poster-em">
        {part}
      </em>
    ) : (
      <Fragment key={i}>{part}</Fragment>
    ),
  )
}
