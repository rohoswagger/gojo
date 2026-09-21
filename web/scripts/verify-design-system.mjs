import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { resolve } from "node:path"

const read = (path) => readFileSync(resolve(path), "utf8")
const globals = read("app/globals.css")
const tokens = read("app/design-tokens.css")
const design = read("DESIGN.md")

assert.ok(
  globals.indexOf('@import "./design-tokens.css"') < globals.indexOf('@import "./skin.css"'),
  "Design tokens must load before component styles"
)

const requiredTokens = [
  "--surface",
  "--ink-1",
  "--gojo-accent",
  "--gojo-warm-ink",
  "--gojo-warm-muted",
  "--gojo-warm-accent",
  "--display",
  "--body",
  "--mono",
  "--step-display",
  "--gutter",
  "--measure",
  "--page",
  "--radius-card",
  "--radius-panel",
]
for (const token of requiredTokens) {
  assert.ok(tokens.includes(`${token}:`), `Missing canonical design token: ${token}`)
}

for (const heading of [
  "## Overview",
  "## Colors",
  "## Typography",
  "## Layout",
  "## Shapes",
  "## Components",
  "## Do's and Don'ts",
]) {
  assert.ok(design.includes(heading), `DESIGN.md is missing ${heading}`)
}

assert.ok(design.includes("app/design-tokens.css"), "DESIGN.md must name the runtime token source")
assert.ok(design.includes("var(--display)"), "DESIGN.md must define display-font usage")
assert.ok(design.includes("var(--body)"), "DESIGN.md must define body-font usage")
assert.ok(design.includes("var(--mono)"), "DESIGN.md must define label-font usage")

const cssFiles = readdirSync(resolve("app"))
  .filter((name) => name.endsWith(".css") && name !== "design-tokens.css")
for (const file of cssFiles) {
  const css = read(`app/${file}`)
  const declarations = [...css.matchAll(/font-family:\s*([^;]+);/g)].map((match) => match[1].trim())
  for (const declaration of declarations) {
    assert.match(
      declaration,
      /^var\(--(?:display|body|mono|font-display|font-body|font-mono-face)\)$/,
      `${file} bypasses the shared font tokens: ${declaration}`
    )
  }
}

console.log("design system contract passed")
