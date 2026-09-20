import assert from "node:assert/strict"
import test from "node:test"
import worker from "../worker.mjs"

const assets = {
  fetch: async () => new Response("asset response", { status: 200 }),
}

test("redirects www requests to the canonical host without changing path or query", async () => {
  const response = await worker.fetch(
    new Request("https://www.trygojo.com/blog/best-window-tiling-apps-mac/?source=search"),
    { ASSETS: assets },
  )

  assert.equal(response.status, 301)
  assert.equal(
    response.headers.get("location"),
    "https://trygojo.com/blog/best-window-tiling-apps-mac/?source=search",
  )
})

test("serves apex requests through the static-assets binding", async () => {
  const response = await worker.fetch(
    new Request("https://trygojo.com/features/window-controls/"),
    { ASSETS: assets },
  )

  assert.equal(response.status, 200)
  assert.equal(await response.text(), "asset response")
})
