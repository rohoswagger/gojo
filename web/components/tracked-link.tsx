"use client"

import Link from "next/link"
import posthog from "posthog-js"
import * as React from "react"

type EventProperties = Record<string, boolean | number | string>

type TrackedLinkProps = Omit<React.ComponentProps<"a">, "href"> & {
  href: string
  eventName: string
  eventProperties?: EventProperties
}

export function TrackedLink({
  href,
  eventName,
  eventProperties,
  onClick,
  children,
  ...props
}: TrackedLinkProps) {
  function handleClick(event: React.MouseEvent<HTMLAnchorElement>) {
    if (
      process.env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN &&
      process.env.NEXT_PUBLIC_POSTHOG_HOST
    ) {
      posthog.capture(eventName, eventProperties)
    }
    onClick?.(event)
  }

  if (href.startsWith("/")) {
    return (
      <Link href={href} onClick={handleClick} {...props}>
        {children}
      </Link>
    )
  }

  return (
    <a href={href} onClick={handleClick} {...props}>
      {children}
    </a>
  )
}
