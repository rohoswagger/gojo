import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const home = readFileSync("out/index.html", "utf8")
const schemas = [...home.matchAll(/<script type="application\/ld\+json">(.*?)<\/script>/gs)]
  .map((match) => JSON.parse(match[1]))
const faq = schemas.find((schema) => schema["@type"] === "FAQPage")
assert.ok(faq, "Homepage needs FAQ schema")
assert.ok(faq.mainEntity.length >= 5, "Homepage should answer setup and purchase questions")
for (const item of faq.mainEntity) {
  assert.equal(item["@type"], "Question")
  assert.equal(item.acceptedAnswer["@type"], "Answer")
  assert.ok(home.includes(item.name), `Visible FAQ missing: ${item.name}`)
  assert.ok(home.includes(item.acceptedAnswer.text), `Visible answer missing: ${item.name}`)
}
assert.match(home, /<details/)
console.log("Homepage visible FAQ and schema agree")
