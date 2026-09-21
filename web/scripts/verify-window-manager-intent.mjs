import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const post = JSON.parse(
  readFileSync(resolve("content/blog/best-window-tiling-apps-mac.json"), "utf8")
)
const expectedTitle = "Best Mac window manager apps: tiling tools compared (2026)"

for (const [label, value] of [
  ["page title", post.title],
  ["Open Graph title", post.og?.["og:title"]],
  ["Twitter title", post.twitter?.["twitter:title"]],
  ["JSON-LD headline", post.jsonLd?.["@graph"]?.[0]?.headline],
  ["rendered H1", post.hero?.title],
]) {
  if (value !== expectedTitle) {
    throw new Error(`${label} must preserve the approved window-manager intent`)
  }
}

if (!post.description?.includes("Mac window manager")) {
  throw new Error("page description must describe the window-manager intent")
}

if (post.canonical !== "https://trygojo.com/blog/best-window-tiling-apps-mac/") {
  throw new Error("intent refresh must preserve the established canonical URL")
}

console.log("window-manager intent contract passed")
