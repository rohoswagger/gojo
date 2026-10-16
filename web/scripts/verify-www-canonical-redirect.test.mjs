import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
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

test("redirects legacy notch guides to the strongest current result without a chain", async () => {
  for (const legacyPath of [
    "/blog/how-to-choose-a-macbook-notch-app/",
    "/blog/best-macbook-notch-apps/",
  ]) {
    for (const host of ["trygojo.com", "www.trygojo.com"]) {
      const response = await worker.fetch(
        new Request(`https://${host}${legacyPath}?source=google`),
        { ASSETS: assets },
      )

      assert.equal(response.status, 301)
      assert.equal(
        response.headers.get("location"),
        "https://trygojo.com/blog/best-mac-notch-apps-for-productivity/?source=google",
      )

      const targetResponse = await worker.fetch(
        new Request(response.headers.get("location")),
        { ASSETS: assets },
      )
      assert.equal(targetResponse.status, 200)
    }
  }
})

test("serves apex requests through the static-assets binding", async () => {
  const response = await worker.fetch(
    new Request("https://trygojo.com/features/window-controls/"),
    { ASSETS: assets },
  )

  assert.equal(response.status, 200)
  assert.equal(await response.text(), "asset response")
})

test("runs the worker before static assets so existing www pages redirect", async () => {
  const config = await readFile(new URL("../wrangler.jsonc", import.meta.url), "utf8")

  assert.match(config, /"binding"\s*:\s*"ASSETS"/)
  assert.match(config, /"run_worker_first"\s*:\s*true/)
})
