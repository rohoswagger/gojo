const CANONICAL_HOST = "trygojo.com"
const LEGACY_HOST = `www.${CANONICAL_HOST}`

const worker = {
  async fetch(request, env) {
    const url = new URL(request.url)

    if (url.hostname.toLowerCase() === LEGACY_HOST) {
      url.hostname = CANONICAL_HOST
      return Response.redirect(url.toString(), 301)
    }

    return env.ASSETS.fetch(request)
  },
}

export default worker
