"use client"

import * as React from "react"

/**
 * Autoplays unless the user has requested reduced motion. Ported verbatim
 * from docs/index.html's inline script (lines 348-364): if reduced motion is
 * on, the video is paused (and paused again on `canplay`, since the poster
 * frame can otherwise flash into a first frame of motion); otherwise it
 * calls `play()` and swallows the rejection the same way the original does.
 */
function AutoplayVideo({
  src,
  poster,
  className,
}: {
  src: string
  poster?: string
  className?: string
}) {
  const videoRef = React.useRef<HTMLVideoElement>(null)

  React.useEffect(() => {
    const video = videoRef.current
    if (!video) return

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    if (reducedMotion) {
      video.pause()
      const pauseOnCanPlay = () => video.pause()
      video.addEventListener("canplay", pauseOnCanPlay)
      return () => video.removeEventListener("canplay", pauseOnCanPlay)
    }

    const playback = video.play()
    if (playback && typeof playback.catch === "function") {
      playback.catch(() => {})
    }
  }, [])

  return (
    <video
      ref={videoRef}
      className={className}
      loop
      muted
      playsInline
      poster={poster}
      aria-hidden="true"
    >
      <source src={src} type="video/mp4" />
    </video>
  )
}

export { AutoplayVideo }
