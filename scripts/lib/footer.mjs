import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const esc = (value) => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");

const LOGO = '<svg viewBox="0 0 256 172.29" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" d="M 130.53 162.06 C 165.62 159.7 195.71 134.68 195.71 134.68 C 246 84.7 246 84.64 245.03 83.6 C 244 82.5 218.71 57.19 217.83 57.52 C 217 57.8 168.66 106.43 166.92 107.91 C 152 120 134.68 122.36 134.68 122.36 C 110 124 88.69 110.52 88.69 110.52 C 82 105 81.57 104.46 81.57 104.46 C 78 101 72.78 101.1 72.78 101.1 C 68 101.5 45.4 123.25 45.4 123.25 C 45.4 123.58 67 144 67.47 143.49 C 90 162 130.53 162.06 130.53 162.06 Z M 37.83 114.87 C 38 115 86.54 66.41 86.54 66.41 C 102 51 132.1 49.61 132.1 49.61 C 165 51.5 169.68 64.16 169.68 64.16 C 182 75 185.76 71.15 185.76 71.15 C 192 69 209.8 49.54 209.8 49.54 C 210 49 208.27 46.9 208.27 46.9 C 204 43 168.13 17.81 168.13 17.81 C 130 -2 86.5 16.02 86.5 16.02 C 50 33 10.17 87.44 10.17 87.44 C 10 88 37.83 114.87 37.83 114.87 Z"/></svg>';

let cache;

async function content() {
  if (!cache) {
    const [features, alternatives] = await Promise.all([
      readFile(path.join(root, "content/features.json"), "utf8").then(JSON.parse),
      readFile(path.join(root, "content/alternatives.json"), "utf8").then(JSON.parse),
    ]);
    cache = { features: features.features, alternatives: alternatives.alternatives };
  }
  return cache;
}

function column(heading, headingHref, links) {
  const title = headingHref ? `<a href="${headingHref}">${heading}</a>` : heading;
  const items = links.map(({ href, label }) => `<li><a href="${href}">${esc(label)}</a></li>`).join("");
  return `<div class="footer-col"><h2 class="footer-heading">${title}</h2><ul class="footer-links">${items}</ul></div>`;
}

// `prefix` is the relative path back to the site root, e.g. "" for docs/index.html
// and "../../" for docs/features/<slug>/index.html.
export async function footerHtml(prefix) {
  const { features, alternatives } = await content();
  const home = prefix || "./";

  const featureLinks = features.map((feature) => ({ href: `${prefix}features/${feature.slug}/`, label: feature.name }));
  const alternativeLinks = alternatives.map((alternative) => ({ href: `${prefix}alternatives/${alternative.slug}/`, label: `${alternative.name} alternative` }));

  const columns = [
    column("Features", `${prefix}features/`, featureLinks),
    column("Alternatives", `${prefix}alternatives/`, alternativeLinks),
    column("Gojo", null, [
      { href: home, label: "Home" },
      { href: `${prefix}#features`, label: "How it works" },
      { href: `${prefix}#buy`, label: "Pricing" },
      { href: `${prefix}blog/`, label: "Blog" },
      { href: "https://downloads.trygojo.com/Gojo.dmg", label: "Download for macOS" },
      { href: "https://github.com/rohoswagger/gojo", label: "GitHub" },
    ]),
  ].join("");

  return `<footer class="footer footer-sitemap"><nav class="footer-cols" aria-label="Footer">${columns}</nav><div class="footer-bottom"><a class="brand" href="${home}" aria-label="Gojo home">${LOGO} Gojo</a><span class="foot-copy">&copy; 2026 Gojo</span></div></footer>`;
}
