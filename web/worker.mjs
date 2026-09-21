const CANONICAL_HOST = "trygojo.com"
const LEGACY_HOST = `www.${CANONICAL_HOST}`
const LEGACY_PATHS = new Set([
  "/blog/how-to-choose-a-macbook-notch-app/",
  "/blog/best-macbook-notch-apps/",
])
const NOTCH_GUIDE_PATH = "/blog/best-mac-notch-apps-for-productivity/"

const worker = {
  async fetch(request, env) {
    const url = new URL(request.url)
    const isLegacyHost = url.hostname.toLowerCase() === LEGACY_HOST
    const normalizedPath = url.pathname.endsWith("/") ? url.pathname : `${url.pathname}/`
    const isLegacyNotchGuide = LEGACY_PATHS.has(normalizedPath)

    if (isLegacyHost || isLegacyNotchGuide) {
      url.hostname = CANONICAL_HOST
      if (isLegacyNotchGuide) url.pathname = NOTCH_GUIDE_PATH
      return Response.redirect(url.toString(), 301)
    }

    return env.ASSETS.fetch(request)
  },
}

export default worker
