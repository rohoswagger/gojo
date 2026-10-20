import assert from "node:assert/strict"
import { existsSync, readFileSync } from "node:fs"
import { resolve } from "node:path"
import { parse } from "node-html-parser"
import { GOJO_RELEASE } from "../lib/release.mjs"

const read = (path) => readFileSync(resolve(path), "utf8")
const compact = (value) => value.replace(/\s+/g, " ").trim()

const project = read("../Gojo.xcodeproj/project.pbxproj")
const releaseVersions = new Set(
  [...project.matchAll(/MARKETING_VERSION = ([0-9.]+);/g)].map((match) => match[1])
)
assert.equal(releaseVersions.size, 1, "All app targets must share one release version")
const [releaseVersion] = releaseVersions
assert.equal(GOJO_RELEASE.version, releaseVersion, "Web release must match the native release version")
assert.equal(GOJO_RELEASE.fileName, `Gojo-${releaseVersion}.dmg`, "Artifact filename must match the release version")
assert.ok(GOJO_RELEASE.downloadUrl.endsWith(`/${GOJO_RELEASE.fileName}`), "Download URL must identify the versioned artifact")

const pressHtml = read("out/press/index.html")
const pressCss = read("app/press.css")
const press = parse(pressHtml)
const pressText = compact(press.textContent)
const pressPage = press.querySelector('.press-page[data-gojo-editorial="warm"]')
assert.ok(pressPage, "Press kit must use Gojo's warm editorial page treatment")
assert.ok(pressPage.querySelector(".press-hero"), "Press kit must use the shared editorial hero structure")
assert.ok(pressPage.querySelector(".press-content"), "Press kit must use the shared editorial content surface")
const homepageText = compact(parse(read("out/index.html")).textContent)
const downloadText = compact(parse(read("out/downloads/index.html")).textContent)

assert.equal(
  press.querySelector('link[rel="canonical"]')?.getAttribute("href"),
  "https://trygojo.com/press/"
)
assert.equal(
  press.querySelector('meta[name="description"]')?.getAttribute("content"),
  "Verified Gojo product facts, review guidance, downloadable assets, pricing, and trial links for journalists and Mac-app creators."
)

for (const expected of [
  "Gojo reviewer kit",
  `Version ${releaseVersion}`,
  "macOS 14 or later",
  "Three days",
  "No account or card",
  "On-device dictation",
  "global dictation shortcut",
  "inserting dictated text into other apps",
  "introductory $9.99 lifetime purchase, regularly $14.99",
  "introductory $19.99 lifetime purchase, regularly $24.99",
]) {
  assert.ok(pressText.includes(expected), `Rendered press kit is missing: ${expected}`)
}

const links = new Map(
  press.querySelectorAll("a[href]").map((link) => [link.getAttribute("href"), link])
)
for (const href of [
  "/assets/demo.mp4",
  "/assets/og.jpg",
  `https://downloads.trygojo.com/Gojo-${releaseVersion}.dmg`,
  "https://github.com/rohoswagger/gojo",
  "/press/",
]) {
  assert.ok(links.has(href), `Rendered press kit is missing link: ${href}`)
}
assert.equal(links.get("/assets/og.jpg")?.getAttribute("download"), "gojo-product-preview.jpg")
assert.match(pressCss, /\.press-demo video\s*\{[^}]*aspect-ratio:\s*1240\s*\/\s*400/s)
assert.doesNotMatch(
  pressCss.match(/\.press-demo video\s*\{[^}]*\}/s)?.[0] ?? "",
  /object-fit:\s*cover/,
  "Press demo must not crop the shipping product UI"
)

for (const asset of ["out/assets/demo.mp4", "out/assets/demo-poster.jpg", "out/assets/og.jpg"]) {
  assert.ok(existsSync(resolve(asset)), `Built press asset is missing: ${asset}`)
}

assert.ok(homepageText.includes("$9.99 one time"))
assert.ok(homepageText.includes("$19.99 one time"))
assert.ok(downloadText.includes(`Version ${releaseVersion}`))
assert.ok(downloadText.includes(GOJO_RELEASE.fileSizeLabel))
assert.ok(downloadText.includes(GOJO_RELEASE.sha256))

const sitemap = read("out/sitemap.xml")
const pressEntry = [...sitemap.matchAll(/<url>\s*([\s\S]*?)\s*<\/url>/g)]
  .map((match) => match[1])
  .find((entry) => entry.includes("<loc>https://trygojo.com/press/</loc>"))
assert.ok(pressEntry, "Generated sitemap is missing the press kit")
const lastmod = JSON.parse(read("content/lastmod.json"))
assert.ok(pressEntry.includes(`<lastmod>${lastmod["/press/"]}</lastmod>`))

console.log("rendered press and reviewer kit contract passed")
