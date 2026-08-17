import { GojoLogo } from "@/components/gojo-logo"
import { altMark } from "@/lib/alt-logos"

function Mark({ slug, name }: { slug: string; name: string }) {
  const mark = altMark(slug, name)
  if (mark.kind === "image") {
    return (
      <span className="versus-mark">
        {/* Small fixed-size PNGs already in public/; next/image would add a
            loader round trip for no gain on a static export. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={mark.src} alt="" width={44} height={44} loading="lazy" />
      </span>
    )
  }
  return (
    <span className="versus-mark" data-monogram="true" aria-hidden="true">
      {mark.text}
    </span>
  )
}

/**
 * The head-to-head at the top of an alternative page.
 *
 * One panel rather than two cards, split by a notch cut into the seam: the
 * comparison device is the shape Gojo lives in. The right half is Gojo's, in
 * brand colour, so there is never a question whose page this is.
 */
export function Versus({
  slug,
  name,
  category,
}: {
  slug: string
  name: string
  category: string
}) {
  return (
    <div className="versus" role="group" aria-label={`${name} compared with Gojo`}>
      <div className="versus-notch">
        <span className="versus-vs">vs</span>
      </div>

      <div className="versus-side">
        <Mark slug={slug} name={name} />
        <span className="versus-name">{name}</span>
        <span className="versus-note">{category}</span>
      </div>

      <div className="versus-side versus-gojo">
        <span className="versus-mark">
          <GojoLogo />
        </span>
        <span className="versus-name">Gojo</span>
        <span className="versus-note">MacBook notch workspace</span>
      </div>
    </div>
  )
}
