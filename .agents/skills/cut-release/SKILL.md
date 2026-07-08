---
name: cut-release
description: Cut, re-cut/override, or roll back a Gojo macOS release (DMG on Cloudflare R2 + Sparkle appcast). Use when asked to "release", "cut a release", "ship a version", "publish vX.Y.Z", "override/re-cut the release", "delete the release", or anything about the release pipeline (scripts/release.sh, make release).
---

# Cutting a Gojo release

Gojo releases are cut locally with `scripts/release.sh` (wrapped as `make release`).
The script: build → code-sign → notarize app → styled DMG → notarize DMG →
Sparkle-sign → update `docs/appcast.xml` → upload DMG to Cloudflare R2 → push tag
→ commit+push appcast. There is **no GitHub Release** — the DMG lives in the
`gojo-downloads` R2 bucket, served at `https://downloads.rohoswagger.com/`.

Each release uploads two R2 objects: the immutable versioned `Gojo-X.Y.Z.dmg`
(what appcast entries point at) and an always-latest `Gojo.dmg` (what the
marketing site's download button points at).

## Three signing modes

- **Developer ID + notarized** (no flag) — **the default: use this unless told
  otherwise.** Fully configured in `.env.local` (`MACOS_SIGNING_IDENTITY` =
  "Developer ID Application: Roshan Desai (L6U44C67P5)" + App Store Connect API
  key vars) and verified working as of v1.0.1. Opens cleanly, no quarantine step.
- **Ad-hoc** (`ARGS=--adhoc`) — no Apple Developer account needed. Ad-hoc signed,
  hardened runtime OFF, not notarized. Only `SPARKLE_PRIVATE_ED_KEY` required.
  Downloaders must clear quarantine once: `xattr -dr com.apple.quarantine /Applications/Gojo.app`.
- **Private** (`ARGS=--private`) — signed + notarized DMG only: no R2 upload, no
  appcast entry (tag only). For paid/paywalled distribution — upload the DMG yourself.

## Pre-release checklist (do this first, every time)

1. **Bump the version** — `MARKETING_VERSION` in `Gojo.xcodeproj/project.pbxproj`
   must equal the release version (the script's pre-flight enforces this). There
   are several occurrences (4 as of 1.0.1); bump them all:
   ```bash
   sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = X.Y.Z;/g" Gojo.xcodeproj/project.pbxproj
   ```
2. **CHANGELOG** — there must be a `## [X.Y.Z]` section in `CHANGELOG.md` (used as
   the Sparkle release notes). Promote `[Unreleased]` and update the link refs at
   the bottom.
3. **Commit + push** the bump, so the working tree is clean and on `main`
   (pre-flight requires clean tree + `main` for a non-dry run). Note: `ez` refuses
   to commit on trunk — release chores go directly on main with raw
   `git commit` + `git push origin main` (the script itself does the same for the
   appcast commit).

## Cut a NEW version

```bash
make release-dry VERSION=X.Y.Z   # optional: full build, stops before publish
make release     VERSION=X.Y.Z   # publish (add ARGS=--adhoc or ARGS=--private if needed)
```

## Override / re-cut an EXISTING version

Re-publishing the same version (e.g. you found a bug right after releasing). R2
uploads simply overwrite, but the tag and appcast do NOT dedup, so tear those
down first, in this order:

```bash
# 1. Delete the remote tag
git push origin :refs/tags/vX.Y.Z

# 2. Delete the LOCAL tag too — it blocks pre-flight
#    ("Tag vX.Y.Z already exists locally") otherwise.
git tag -d vX.Y.Z 2>/dev/null || true

# 3. Remove the old appcast entry — update_appcast.py PREPENDS with no dedup, so
#    re-running would create a SECOND vX.Y.Z <item>. Revert the appcast commit
#    (find it: git log --oneline -- docs/appcast.xml), then push.
git revert --no-edit <appcast-commit-sha>
git push origin main

# 4. Re-cut (overwrites the R2 objects)
make release VERSION=X.Y.Z
```

Verify after step 3: `grep -c '<title>Version X.Y.Z' docs/appcast.xml` → `0`.

## Roll back / delete a release (no re-cut)

```bash
git push origin :refs/tags/vX.Y.Z
git tag -d vX.Y.Z 2>/dev/null || true
git revert --no-edit <appcast-commit-sha> && git push origin main   # so Sparkle stops offering it

# Optionally delete the versioned DMG from R2:
CLOUDFLARE_ACCOUNT_ID=54b7185040a2db03ec87bee9cd65135f \
  npx --yes wrangler@4 r2 object delete --remote "gojo-downloads/Gojo-X.Y.Z.dmg"
```

**`Gojo.dmg` (latest) still points at the rolled-back build** — re-upload the
previous version's DMG over it, or the marketing site serves the bad build:

```bash
CLOUDFLARE_ACCOUNT_ID=54b7185040a2db03ec87bee9cd65135f \
  npx --yes wrangler@4 r2 object put --remote --content-type application/x-apple-diskimage \
  --file Gojo-<prev>.dmg "gojo-downloads/Gojo.dmg"
```

## ALWAYS verify the published DMG launches

The DMG must be downloaded + launch-tested — a build can publish fine yet crash on
launch (we shipped a broken one once: hardened runtime + ad-hoc → library
validation killed it loading a vendored framework). After any release:

```bash
cd /tmp && rm -rf rv && mkdir rv && cd rv
curl -fsSLO https://downloads.rohoswagger.com/Gojo-X.Y.Z.dmg
shasum -a 256 Gojo-X.Y.Z.dmg          # compare against the script's printed SHA-256
MP=$(hdiutil attach Gojo-X.Y.Z.dmg -nobrowse -readonly | grep -o '/Volumes/.*')
codesign -dv --verbose=2 "$MP/Gojo.app" 2>&1 | grep -i flags
# Developer ID: want 0x10000(runtime); adhoc: want 0x2(adhoc), NO "runtime"
spctl -a -vv -t exec "$MP/Gojo.app"   # Developer ID: want "source=Notarized Developer ID"
cp -R "$MP/Gojo.app" t.app && hdiutil detach "$MP" >/dev/null
t.app/Contents/MacOS/Gojo & P=$!; sleep 6
kill -0 $P 2>/dev/null && echo "LAUNCHES" && kill $P || echo "CRASHED"
cd - >/dev/null && rm -rf /tmp/rv
```

## Gotchas

- **Stale `.build/` caches after the repo moves on disk** (bit us cutting 1.0.1):
  SPM's `workspace-state.json` and the dmgbuild venv both record **absolute
  paths**. If the checkout has moved, the build fails with "There is no
  XCFramework found at …" (pointing at the old path) and later
  `dmgbuild: bad interpreter`. `make clean` does NOT fix it — it only removes
  `.build/DerivedData`. Fix:
  ```bash
  rm -rf .build/release/SourcePackages .build/release/Build .build/dmg-venv
  ```
- **wrangler auth**: R2 upload needs a Cloudflare OAuth login (`npx wrangler login`).
  The script pins `CLOUDFLARE_ACCOUNT_ID=54b7185040a2db03ec87bee9cd65135f` so it
  never prompts for an account.
- **Ad-hoc + hardened runtime**: `--adhoc` forces `ENABLE_HARDENED_RUNTIME=NO`.
  Never ad-hoc-sign with hardened runtime — library validation crashes it at launch.
- **Appcast path**: it lives at `docs/appcast.xml` (GitHub Pages serves `/docs`),
  not the repo root.
- **Sparkle key**: `SPARKLE_PRIVATE_ED_KEY` in `.env.local` may be a file path OR
  the raw key value (both supported). It is the one irreplaceable secret — losing
  it breaks auto-updates for all installs.
- **GitHub Pages** must stay enabled (Settings → Pages → `main` / `/docs`) or the
  appcast (auto-update feed) 404s.

## After publishing

- GitHub Pages rebuilds the appcast feed automatically (~1 min):
  `gh api repos/rohoswagger/gojo/pages/builds/latest --jq '.status'`.
- The Pages site uses a custom domain: `rohoswagger.github.io/gojo/appcast.xml`
  **301-redirects** to `gojo.rohoswagger.com/appcast.xml`. Check the live feed
  with `curl -fsSL` (follow redirects) or the canonical URL directly:
  ```bash
  curl -fsSL https://gojo.rohoswagger.com/appcast.xml | grep "Version X.Y.Z"
  ```
- Existing installs auto-update via Sparkle within ~24h (or on manual check).
