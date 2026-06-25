---
name: cut-release
description: Cut, re-cut/override, or roll back a Gojo macOS release (DMG + GitHub Release + Sparkle appcast). Use when asked to "release", "cut a release", "ship a version", "publish vX.Y.Z", "override/re-cut the release", "delete the release", or anything about the release pipeline (scripts/release.sh, make release).
---

# Cutting a Gojo release

Gojo releases are cut locally with `scripts/release.sh` (wrapped as `make release`).
The script: build → code-sign → (notarize) → styled DMG → Sparkle-sign → update
`docs/appcast.xml` → GitHub Release → commit+push appcast.

## Two signing modes

- **Ad-hoc** (`ARGS=--adhoc`) — **the default for this project.** No Apple Developer
  account needed. App is ad-hoc signed (`CODE_SIGN_IDENTITY="-"`), hardened runtime
  OFF, not notarized. Only `SPARKLE_PRIVATE_ED_KEY` is required in `.env.local`.
  Downloaders must clear quarantine once: `xattr -dr com.apple.quarantine /Applications/Gojo.app`.
- **Developer ID + notarized** (no flag) — needs a paid Apple Developer Program:
  `MACOS_SIGNING_IDENTITY` (Developer ID Application cert) + App Store Connect API
  key vars in `.env.local`. Opens cleanly with no quarantine step. The project's
  `DEVELOPMENT_TEAM` in `scripts/release.sh` is `L6U44C67P5` (the upstream fork's
  team) — change it to the account's own team before using this path.

Unless told otherwise, use **`--adhoc`**.

## Pre-release checklist (do this first, every time)

1. **Bump the version** — `MARKETING_VERSION` in `Gojo.xcodeproj/project.pbxproj`
   must equal the release version (the script's pre-flight enforces this). There
   are 2 occurrences; bump both:
   ```bash
   sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = X.Y.Z;/g" Gojo.xcodeproj/project.pbxproj
   ```
2. **CHANGELOG** — there must be a `## [X.Y.Z]` section in `CHANGELOG.md` (used as
   the GitHub Release body + Sparkle notes). Promote `[Unreleased]`.
3. **Commit + push** the bump, so the working tree is clean and on `main`
   (pre-flight requires clean tree + `main` for a non-dry run).

## Cut a NEW version

```bash
make release-dry VERSION=X.Y.Z ARGS=--adhoc   # optional: full build, stops before publish
make release     VERSION=X.Y.Z ARGS=--adhoc   # publish
```

## Override / re-cut an EXISTING version

Re-publishing the same version (e.g. you found a bug right after releasing). The
pipeline does NOT dedup, so you must tear the old one down first, in this order:

```bash
# 1. Delete the GitHub release AND the remote tag
gh release delete vX.Y.Z -R rohoswagger/gojo --yes --cleanup-tag

# 2. Delete the LOCAL tag too — it lingers after the remote delete and will
#    block pre-flight ("Tag vX.Y.Z already exists locally") otherwise.
git tag -d vX.Y.Z 2>/dev/null || true

# 3. Remove the old appcast entry — update_appcast.py PREPENDS with no dedup, so
#    re-running would create a SECOND vX.Y.Z <item>. Revert the appcast commit
#    (find it: git log --oneline -- docs/appcast.xml), then push.
git revert --no-edit <appcast-commit-sha>
git push origin main

# 4. Re-cut
make release VERSION=X.Y.Z ARGS=--adhoc
```

Verify after step 3: `grep -c '<title>Version X.Y.Z' docs/appcast.xml` → `0`.

## Roll back / delete a release (no re-cut)

```bash
gh release delete vX.Y.Z -R rohoswagger/gojo --yes --cleanup-tag
git tag -d vX.Y.Z 2>/dev/null || true
git revert --no-edit <appcast-commit-sha> && git push origin main   # so Sparkle won't 404
```

## ALWAYS verify the published DMG launches

The DMG must be downloaded + launch-tested — a build can publish fine yet crash on
launch (we shipped a broken one once: hardened runtime + ad-hoc → library
validation killed it loading a vendored framework). After any release:

```bash
cd /tmp && rm -rf rv && mkdir rv
gh release download vX.Y.Z -R rohoswagger/gojo --dir rv
DMG=$(ls rv/*.dmg)
MP=$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*')
codesign -dv --verbose=2 "$MP/Gojo.app" 2>&1 | grep -i flags   # adhoc: want 0x2(adhoc), NO "runtime"
cp -R "$MP/Gojo.app" rv/t.app && hdiutil detach "$MP" >/dev/null
rv/t.app/Contents/MacOS/Gojo & P=$!; sleep 5
kill -0 $P 2>/dev/null && echo "LAUNCHES" && kill $P || echo "CRASHED"
cd - >/dev/null && rm -rf /tmp/rv
```

## Gotchas (all already handled in scripts/release.sh — don't reintroduce)

- **gh default remote**: the repo has multiple remotes; `gh release` calls pass
  `-R rohoswagger/gojo` so they don't need `gh repo set-default`.
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
- Existing installs auto-update via Sparkle within ~24h (or on manual check).
