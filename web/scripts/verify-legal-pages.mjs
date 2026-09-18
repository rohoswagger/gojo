import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const source = (path) => readFileSync(resolve(path), "utf8")
const footer = source("components/gojo-footer.tsx")
const privacy = source("app/privacy/page.tsx")
const terms = source("app/terms/page.tsx")
const sitemap = source("app/sitemap.ts")
const styles = source("app/globals.css")

for (const [label, page, canonical] of [
  ["Privacy", privacy, "https://trygojo.com/privacy/"],
  ["Terms", terms, "https://trygojo.com/terms/"],
]) {
  if (!page.includes(`title: "${label}`)) {
    throw new Error(`${label} page must define a page-specific title`)
  }
  if (!page.includes(canonical)) {
    throw new Error(`${label} page must define its canonical URL`)
  }
  if (!page.includes("<GojoHeader />") || !page.includes("<GojoFooter />") || !page.includes('className="legal-content mt-12"')) {
    throw new Error(`${label} page must use the shared site navigation and legal content styling`)
  }
}

for (const required of ['{ href: "/privacy/", label: "Privacy" }', '{ href: "/terms/", label: "Terms" }']) {
  if (!footer.includes(required)) {
    throw new Error(`Footer must include ${required}`)
  }
}

for (const required of [".legal-content h2", ".legal-content ul", ".legal-content a"]) {
  if (!styles.includes(required)) throw new Error(`Legal-page styling is missing ${required}`)
}

for (const required of ["PostHog", "Query strings and URL fragments are removed", "does not set a cookie or stable browser identifier"]) {
  if (!privacy.includes(required)) throw new Error(`Privacy page is missing ${required}`)
}

for (const path of ['"/privacy/"', '"/terms/"']) {
  if (!sitemap.includes(path)) throw new Error(`Sitemap must include ${path}`)
}

console.log("legal page source contract passed")
