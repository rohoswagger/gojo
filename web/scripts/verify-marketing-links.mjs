import { existsSync, readFileSync, readdirSync } from "node:fs"
import { parse } from "node-html-parser"

const childRoutes = (section) =>
  readdirSync(`out/${section}`, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(`out/${section}/${entry.name}/index.html`))
    .map((entry) => `${section}/${entry.name}`)

const routes = ["", "features", ...childRoutes("features"), "alternatives", ...childRoutes("alternatives"), "blog", ...childRoutes("blog"), "downloads"]

const requiredSiteLinks = ["/features/", "/#buy", "/blog/", "/downloads/"]

for (const route of routes) {
  const file = route ? `out/${route}/index.html` : "out/index.html"
  const root = parse(readFileSync(file, "utf8"))
  const header = root.querySelector(".site-header")
  if (!header) throw new Error(`${route || "/"}: missing site header`)
  const links = header.querySelectorAll("a").map((link) => link.getAttribute("href"))
  const expected = ["/", ...(route === "" ? ["#features", "#buy", "/blog/", "/downloads/"] : requiredSiteLinks)]
  if (JSON.stringify(links) !== JSON.stringify(expected)) {
    throw new Error(`${route || "/"}: header links ${JSON.stringify(links)} do not match ${JSON.stringify(expected)}`)
  }
}

const guides = [
  ["local-dictation", "best-local-dictation-apps-mac"],
  ["window-controls", "best-window-tiling-apps-mac"],
  ["file-shelf", "best-file-shelf-apps-mac"],
]

for (const [featureSlug, guideSlug] of guides) {
  if (!existsSync(`out/blog/${guideSlug}/index.html`)) throw new Error(`missing ${guideSlug} output`)
  const feature = readFileSync(`out/features/${featureSlug}/index.html`, "utf8")
  if (!feature.includes(`/blog/${guideSlug}/`)) {
    throw new Error(`${featureSlug} does not link to ${guideSlug}`)
  }
}

console.log("marketing header and blog-link checks passed")
