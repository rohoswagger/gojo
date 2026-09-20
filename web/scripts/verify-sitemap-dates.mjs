import { readFileSync, readdirSync } from "node:fs"
import { resolve } from "node:path"

const readJson = (path) => JSON.parse(readFileSync(resolve(path), "utf8"))
const isoDate = /^\d{4}-\d{2}-\d{2}$/

function assertVaried(label, dates) {
  if (dates.length === 0) throw new Error(`${label} has no dates to verify`)
  if (dates.some((date) => !isoDate.test(date))) {
    throw new Error(`${label} contains a non-ISO date`)
  }

  const counts = new Map()
  for (const date of dates) counts.set(date, (counts.get(date) ?? 0) + 1)

  const distinctRatio = counts.size / dates.length
  const largestCluster = Math.max(...counts.values())
  const largestShare = largestCluster / dates.length

  if (distinctRatio < 0.5 || largestShare > 0.2) {
    throw new Error(
      `${label} dates are insufficiently varied: ${counts.size}/${dates.length} distinct, largest cluster ${largestCluster}/${dates.length}`
    )
  }
}

const hub = readJson("content/blog/_hub.json")
const hubPosts = new Map(hub.posts.map((post) => [post.slug, post]))
const blogPosts = readdirSync(resolve("content/blog"))
  .filter((file) => file.endsWith(".json") && file !== "_hub.json")
  .map((file) => readJson(`content/blog/${file}`))

const blogDates = blogPosts.map((post) => post.article.published_time)
assertVaried("Blog publication", blogDates)

for (const post of blogPosts) {
  const hubPost = hubPosts.get(post.slug)
  if (!hubPost) throw new Error(`Blog hub is missing ${post.slug}`)

  const formatted = new Intl.DateTimeFormat("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${post.article.published_time}T00:00:00Z`))

  if (hubPost.date !== formatted) {
    throw new Error(`Blog hub date mismatch for ${post.slug}: ${hubPost.date}`)
  }
}

const sitemap = readFileSync(resolve("out/sitemap.xml"), "utf8")
const sitemapEntries = [...sitemap.matchAll(/<url>\s*([\s\S]*?)\s*<\/url>/g)].map((match) => ({
  loc: match[1].match(/<loc>([^<]+)<\/loc>/)?.[1],
  lastmod: match[1].match(/<lastmod>([^<]+)<\/lastmod>/)?.[1] ?? null,
}))
const datedSitemapEntries = sitemapEntries.filter((entry) => entry.lastmod)
assertVaried(
  "Sitemap lastmod",
  datedSitemapEntries.map((entry) => entry.lastmod)
)

const sitemapByLocation = new Map(sitemapEntries.map((entry) => [entry.loc, entry]))
for (const post of blogPosts) {
  if (!sitemapByLocation.has(post.canonical)) {
    throw new Error(`Sitemap is missing blog post ${post.canonical}`)
  }
}

console.log("sitemap and blog date variance checks passed")
