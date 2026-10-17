# Gojo website

The marketing site uses Next.js with static export. Article data lives in
`content/blog`. Feature and alternative pages use the HTML generators in `lib`.
Shared coastal styles live in `app/marketing-heroes.css` over the base `app/skin.css`. React actions use the local SwagUI
`Button` in `components/ui/button.tsx`.

## Run locally

From `web`, install the locked dependencies and start the development server.

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Open `http://localhost:3000`. Run the source checks before a build.

```sh
pnpm lint
pnpm exec tsc --noEmit
```

`pnpm build` writes the static site to `out` and runs the marketing link and
accessibility checks, followed by the full route crawl. `pnpm verify:marketing`,
`pnpm verify:accessibility` and `pnpm audit:site` check an existing export.
The route crawl validates local assets, fragments, landmarks, canonicals and download tracking.

## Update release details

`lib/release.ts` pairs the download page's version, immutable artifact URL, byte
size and SHA-256. The homepage also uses this release record for its version.
Keep the versioned URL and checksum together. The mutable `Gojo.dmg` alias can
change after a release.

Before updating the record, compare `../appcast.xml` with the release tag and
download the versioned artifact. Read the actual byte count and SHA-256.

```sh
curl --fail --location --output /tmp/Gojo-1.5.1.dmg https://downloads.trygojo.com/Gojo-1.5.1.dmg
wc -c < /tmp/Gojo-1.5.1.dmg
shasum -a 256 /tmp/Gojo-1.5.1.dmg
```

The published artifact was checked on 2026-10-16. The GET returned HTTP 200 at
`https://downloads.trygojo.com/Gojo-1.5.1.dmg`. Its 17,217,841 bytes match the
appcast enclosure. Tag `v1.5.1` sets the app's marketing version to `1.5.1`.
Its SHA-256 is
`510c5e9d8c3732a1cd8c91925d2c4a15d586d51e5468a985632bd2ada1a3b814`.

## Preserve page behavior

Keep each route's heading and body in one focusable `main#main-content`, with the
header outside. Preserve blog canonicals, article JSON-LD, fragment IDs and
article content. Use existing screenshots at their native aspect ratios.

Direct DMG links carry `data-funnel-event="download_cta_clicked"` and a fixed
`data-funnel-placement` value such as `downloads` or `blog_article`. Keep license
links and purchase attribution intact.
