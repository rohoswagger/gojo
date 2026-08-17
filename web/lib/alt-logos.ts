/**
 * Marks for the alternatives.
 *
 * Only four of the twelve ship a logo in public/assets/utilities/. The rest
 * fall back to a monogram tile so the versus layout is complete either way —
 * dropping a file in and adding a line below is all it takes to upgrade one.
 *
 * These are third-party marks used for identification in comparison content;
 * every page carries the "not affiliated with or endorsed by" note.
 */
const LOGO_FILES: Record<string, string> = {
  "boring-notch": "boringnotch.png",
  flux: "flux.png",
  maccy: "maccy.png",
  rectangle: "rectangle.png",
}

export type AltMark =
  | { kind: "image"; src: string }
  | { kind: "monogram"; text: string }

/** "BetterTouchTool" -> "BT", "Raycast" -> "R", "f.lux" -> "F". */
function monogram(name: string): string {
  const caps = name.match(/[A-Z]/g)
  if (caps && caps.length > 1) return caps.slice(0, 2).join("")
  return name.replace(/[^A-Za-z]/g, "").charAt(0).toUpperCase()
}

export function altMark(slug: string, name: string): AltMark {
  const file = LOGO_FILES[slug]
  if (file) return { kind: "image", src: `/assets/utilities/${file}` }
  return { kind: "monogram", text: monogram(name) }
}

/** The same mark as an HTML string, for the pages lib/ renders as markup. */
export function altMarkHtml(slug: string, name: string, className = "alt-mark"): string {
  const mark = altMark(slug, name)
  if (mark.kind === "image") {
    return `<span class="${className}"><img src="${mark.src}" alt="" width="40" height="40" loading="lazy"></span>`
  }
  return `<span class="${className}" data-monogram="true" aria-hidden="true">${mark.text}</span>`
}
