import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import { parse } from "node-html-parser"

function htmlFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = join(directory, entry.name)
    return entry.isDirectory() ? htmlFiles(file) : entry.name.endsWith(".html") ? [file] : []
  })
}

const files = htmlFiles("out")
assert.ok(files.length > 0, "Build the site before verifying accessibility")
for (const file of files) {
  const page = parse(readFileSync(file, "utf8"))
  assert.equal(page.querySelectorAll("main").length, 1, `${file}: expected one main landmark`)
  const targets = page.querySelectorAll('[id="main-content"]')
  assert.equal(targets.length, 1, `${file}: expected one content skip destination`)
  assert.equal(targets[0].getAttribute("tabindex"), "-1", `${file}: skip destination must accept focus`)
  assert.ok(page.querySelector('a.skip-link[href="#main-content"]'), `${file}: missing content skip link`)
  assert.ok(page.querySelector("h1"), `${file}: missing page heading`)
  for (const image of page.querySelectorAll("img")) {
    assert.ok(image.hasAttribute("alt"), `${file}: image lacks alternative text`)
  }
}
console.log(`Accessibility structure passed for ${files.length} exported pages`)
