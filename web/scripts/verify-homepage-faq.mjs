import { readFileSync } from "node:fs"
import { resolve } from "node:path"

const home = readFileSync(resolve("app/page.tsx"), "utf8")

for (const required of [
  "const faqItems = [",
  '"@type": "FAQPage"',
  "<section className=\"content-band\" aria-labelledby=\"faq-heading\">",
  "<details",
  "Does Gojo keep dictation on my Mac?",
  "Does Gojo work on more than one Mac?",
]) {
  if (!home.includes(required)) {
    throw new Error(`Homepage FAQ implementation is missing ${required}`)
  }
}

console.log("homepage FAQ source contract passed")
