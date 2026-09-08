import { GOJO_LOGO_PATH } from "@/lib/site-header"

/** The Gojo mark. Shared by the header, the footer and the homepage diagram. */
export function GojoLogo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true" className={className}>
      <path
        fillRule="evenodd"
        d={GOJO_LOGO_PATH}
      />
    </svg>
  )
}
