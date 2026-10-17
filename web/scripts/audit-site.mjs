import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs"
import { join, relative } from "node:path"
import { parse } from "node-html-parser"

function filesAt(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = join(directory, entry.name)
    return entry.isDirectory() ? filesAt(file) : entry.name.endsWith(".html") ? [file] : []
  })
}

const origin = "https://trygojo.com"
const pages = filesAt("out").map((file) => {
  const path = `/${relative("out", file).replace(/index\.html$/, "")}`
  return { file, path, root: parse(readFileSync(file, "utf8")) }
})
const byFile = new Map(pages.map((page) => [page.file, page]))
const issues = []
const problem = (path, rule, target) => issues.push({ path, rule, target })

function localFile(pathname) {
  const decoded = decodeURIComponent(pathname)
  const exact = join("out", decoded)
  if (existsSync(exact) && statSync(exact).isFile()) return exact
  const index = join(exact, "index.html")
  return existsSync(index) ? index : null
}

const routes = pages.map(({ file, path, root }) => {
  const family = path.includes("404") ? "not-found" : path === "/" ? "home" : path.split("/")[1]
  const mains = root.querySelectorAll("main")
  if (mains.length !== 1) problem(path, "one-main", mains.length)
  if (!mains[0]?.querySelector("h1")) problem(path, "heading-in-main", "h1")
  if (root.querySelectorAll('[id="main-content"]').length !== 1) problem(path, "one-skip-target", "main-content")
  if (!root.querySelector('a.skip-link[href="#main-content"]')) problem(path, "skip-link", "main-content")

  const ids = new Set()
  for (const element of root.querySelectorAll("[id]")) {
    const id = element.getAttribute("id")
    if (ids.has(id)) problem(path, "unique-id", id)
    ids.add(id)
  }

  let downloads = 0
  for (const anchor of root.querySelectorAll("a[href]")) {
    const href = anchor.getAttribute("href")
    if (!href || /^(mailto:|tel:|javascript:)/i.test(href)) continue
    let url
    try { url = new URL(href, `${origin}${path}`) } catch { problem(path, "valid-link", href); continue }
    const isDownload = url.hostname === "downloads.trygojo.com" && url.pathname.endsWith(".dmg")
    if (isDownload) {
      downloads++
      if (anchor.getAttribute("data-funnel-event") !== "download_cta_clicked") problem(path, "tracked-download", href)
    }
    if (anchor.getAttribute("data-funnel-event") === "download_cta_clicked" && !isDownload) problem(path, "honest-download-event", href)
    if (url.origin !== origin && url.hostname !== "www.trygojo.com") continue
    const target = localFile(url.pathname)
    if (!target) { problem(path, "internal-link", href); continue }
    if (url.hash && byFile.has(target)) {
      const id = decodeURIComponent(url.hash.slice(1))
      const destination = byFile.get(target).root
      if (!destination.querySelectorAll("[id]").some((element) => element.getAttribute("id") === id)) problem(path, "fragment-target", href)
    }
  }

  for (const image of root.querySelectorAll("img")) {
    const src = image.getAttribute("src")
    if (!image.hasAttribute("alt")) problem(path, "image-alt", src)
    if (!src || /^(https?:|data:|blob:)/i.test(src)) continue
    const url = new URL(src, `${origin}${path}`)
    if (!localFile(url.pathname)) problem(path, "image-asset", src)
    if (!image.getAttribute("width") || !image.getAttribute("height")) problem(path, "reserved-image-space", src)
  }

  const canonical = root.querySelector('link[rel="canonical"]')?.getAttribute("href")
  if (family !== "not-found" && canonical !== `${origin}${path}`) problem(path, "canonical-route", canonical)
  return {
    path, file, family,
    title: root.querySelector("title")?.textContent,
    heading: root.querySelector("h1")?.textContent,
    images: root.querySelectorAll("img").length,
    downloads,
    swaguiButtons: root.querySelectorAll('[data-slot="button"]').length,
    swaguiSections: root.querySelectorAll('[data-slot="section"]').length,
  }
})

const summary = {
  pages: routes.length,
  families: [...new Set(routes.map((route) => route.family))],
  downloadActions: routes.reduce((sum, route) => sum + route.downloads, 0),
  swaguiButtons: routes.reduce((sum, route) => sum + route.swaguiButtons, 0),
  issues: issues.length,
}
const report = { summary, routes, issues }
const outputIndex = process.argv.indexOf("--report")
if (outputIndex >= 0 && process.argv[outputIndex + 1]) writeFileSync(process.argv[outputIndex + 1], JSON.stringify(report, null, 2) + "\n")
console.log(JSON.stringify(summary))
if (issues.length) {
  console.error(JSON.stringify(issues.slice(0, 40), null, 2))
  process.exitCode = 1
}
