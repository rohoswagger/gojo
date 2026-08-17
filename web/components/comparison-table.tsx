import { Check, Minus, X } from "lucide-react"

import { GojoLogo } from "@/components/gojo-logo"
import { altMark } from "@/lib/alt-logos"

/**
 * A cell is either a sourced value, a yes/no, or an explicit gap. "unknown"
 * is a first-class state on purpose: these pages compare third-party products
 * from their own published material, and an empty cell must read as "they do
 * not publish this", never as a silent "no".
 */
export type Cell =
  | { kind: "yes"; note?: string }
  | { kind: "no"; note?: string }
  | { kind: "unknown" }
  | { kind: "text"; text: string }

export const yes = (note?: string): Cell => ({ kind: "yes", note })
export const no = (note?: string): Cell => ({ kind: "no", note })
export const unknown: Cell = { kind: "unknown" }
export const text = (t: string): Cell => ({ kind: "text", text: t })

export type ComparisonRow = {
  label: string
  note?: string
  gojo: Cell
  alt: Cell
}

function CellView({ cell }: { cell: Cell }) {
  if (cell.kind === "yes" || cell.kind === "no") {
    const Icon = cell.kind === "yes" ? Check : X
    return (
      <span className="cmp-flag" data-flag={cell.kind}>
        <Icon aria-hidden="true" />
        <span>{cell.kind === "yes" ? "Yes" : "No"}</span>
        {cell.note ? <em>{cell.note}</em> : null}
      </span>
    )
  }
  if (cell.kind === "unknown") {
    return (
      <span className="cmp-flag" data-flag="unknown">
        <Minus aria-hidden="true" />
        <span>Not published</span>
      </span>
    )
  }
  return <span className="cmp-value">{cell.text}</span>
}

function Head({
  name,
  kicker,
  mark,
  primary,
}: {
  name: string
  kicker: string
  mark: React.ReactNode
  primary?: boolean
}) {
  return (
    <div className="cmp-head" data-primary={primary ? "true" : undefined}>
      {mark}
      <span className="cmp-head-name">{name}</span>
      <span className="cmp-head-kicker">{kicker}</span>
    </div>
  )
}

function AltMark({ slug, name }: { slug: string; name: string }) {
  const mark = altMark(slug, name)
  if (mark.kind === "image") {
    return (
      <span className="cmp-mark">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={mark.src} alt="" width={32} height={32} loading="lazy" />
      </span>
    )
  }
  return (
    <span className="cmp-mark" data-monogram="true" aria-hidden="true">
      {mark.text}
    </span>
  )
}

export function ComparisonTable({
  slug,
  name,
  category,
  rows,
  footnote,
}: {
  slug: string
  name: string
  category: string
  rows: ComparisonRow[]
  footnote?: string
}) {
  return (
    <div className="cmp">
      <div className="cmp-grid" role="table" aria-label={`Gojo compared with ${name}`}>
        <div className="cmp-row cmp-row-head" role="row">
          <div className="cmp-cell cmp-cell-label cmp-cell-corner" role="columnheader">
            <span className="cmp-corner">Feature</span>
          </div>
          <div className="cmp-cell" role="columnheader">
            <Head
              name="Gojo"
              kicker="MacBook notch workspace"
              mark={
                <span className="cmp-mark cmp-mark-gojo">
                  <GojoLogo />
                </span>
              }
              primary
            />
          </div>
          <div className="cmp-cell" role="columnheader">
            <Head name={name} kicker={category} mark={<AltMark slug={slug} name={name} />} />
          </div>
        </div>

        {rows.map((row) => (
          <div className="cmp-row" role="row" key={row.label}>
            <div className="cmp-cell cmp-cell-label" role="rowheader">
              <span className="cmp-label">{row.label}</span>
              {row.note ? <span className="cmp-note">{row.note}</span> : null}
            </div>
            <div className="cmp-cell" data-primary="true" role="cell">
              <CellView cell={row.gojo} />
            </div>
            <div className="cmp-cell" role="cell">
              <CellView cell={row.alt} />
            </div>
          </div>
        ))}
      </div>

      {footnote ? <p className="cmp-footnote">{footnote}</p> : null}
    </div>
  )
}
